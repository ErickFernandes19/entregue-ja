package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

@Component
public class ConciliacaoPagamentosScheduler {

    private static final Logger LOGGER = LoggerFactory.getLogger(ConciliacaoPagamentosScheduler.class);

    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final AssinaturaRecorrenteRepository recorrenteRepository;
    private final AssinaturaRecorrenteService assinaturaRecorrenteService;
    private final PagamentoAssinaturaService pagamentoService;
    private final AtomicBoolean executando = new AtomicBoolean(false);

    public ConciliacaoPagamentosScheduler(
            PagamentoAssinaturaRepository pagamentoRepository,
            AssinaturaRecorrenteRepository recorrenteRepository,
            AssinaturaRecorrenteService assinaturaRecorrenteService,
            PagamentoAssinaturaService pagamentoService
    ) {
        this.pagamentoRepository = pagamentoRepository;
        this.recorrenteRepository = recorrenteRepository;
        this.assinaturaRecorrenteService = assinaturaRecorrenteService;
        this.pagamentoService = pagamentoService;
    }

    @Scheduled(
            fixedDelayString = "${pagamentos.conciliacao.intervalo-ms:3600000}",
            initialDelayString = "${pagamentos.conciliacao.atraso-inicial-ms:120000}"
    )
    public void executar() {
        if (!executando.compareAndSet(false, true)) {
            return;
        }

        try {
            Set<ContaConciliacao> contas = new LinkedHashSet<>();
            Set<PixRecuperacao> pixSemIdentificador = new LinkedHashSet<>();

            for (PagamentoAssinatura pagamento : pagamentoRepository.findByStatusOrderByDataCriacaoAsc(
                    PagamentoAssinatura.Status.PENDENTE)) {
                adicionarPagamento(contas, pixSemIdentificador, pagamento);
            }

            for (PagamentoAssinatura pagamento : pagamentoRepository.findByStatusOrderByDataCriacaoAsc(
                    PagamentoAssinatura.Status.APROVADO)) {
                if (pagamento.getDataVencimento() == null) {
                    adicionarPagamento(contas, pixSemIdentificador, pagamento);
                }
            }

            for (AssinaturaRecorrente recorrente : recorrenteRepository.findAll()) {
                if (recorrente.getMercadoPagoAssinaturaId() != null
                        && !recorrente.getMercadoPagoAssinaturaId().isBlank()) {
                    ContaConciliacao conta = identificarConta(recorrente.getEmpresaId(), recorrente.getEntregadorId());
                    if (conta != null) {
                        contas.add(conta);
                    }
                }
            }

            int empresas = 0;
            int entregadores = 0;
            int sucesso = 0;
            int falhas = 0;

            for (ContaConciliacao conta : contas) {
                if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                    empresas++;
                } else {
                    entregadores++;
                }

                try {
                    var resultado = conta.tipo() == Assinatura.TipoConta.EMPRESA
                            ? assinaturaRecorrenteService.conciliarPagamentos(conta.id())
                            : assinaturaRecorrenteService.conciliarPagamentos(conta.tipo(), conta.id());

                    Object falhasInternas = resultado.get("falhas");
                    if (falhasInternas instanceof Number numero && numero.intValue() == 0) {
                        sucesso++;
                    } else {
                        falhas++;
                        LOGGER.warn("Conciliação da conta {}:{} retornou falhas ou resultado inválido: {}",
                                conta.tipo(), conta.id(), falhasInternas);
                    }
                } catch (Exception e) {
                    falhas++;
                    LOGGER.error("Falha ao conciliar pagamentos da conta {}:{}",
                            conta.tipo(), conta.id(), e);
                }
            }

            if (!contas.isEmpty()) {
                LOGGER.info("Conciliação regular concluída: {} contas, {} empresas, {} entregadores, {} sem falhas, {} com falha",
                        contas.size(), empresas, entregadores, sucesso, falhas);
            }

            recuperarPixSemIdentificador(pixSemIdentificador);
        } catch (Exception e) {
            LOGGER.error("Falha ao executar a conciliação automática de pagamentos", e);
        } finally {
            executando.set(false);
        }
    }

    private void adicionarPagamento(
            Set<ContaConciliacao> contas,
            Set<PixRecuperacao> pixSemIdentificador,
            PagamentoAssinatura pagamento
    ) {
        ContaConciliacao conta = identificarConta(pagamento.getEmpresaId(), pagamento.getEntregadorId());
        if (conta == null) {
            return;
        }
        contas.add(conta);
        if (pagamento.getFormaPagamento() == PagamentoAssinatura.FormaPagamento.PIX
                && (pagamento.getMercadoPagoPagamentoId() == null
                || pagamento.getMercadoPagoPagamentoId().isBlank())) {
            if (pagamento.getId() == null || pagamento.getId() <= 0) {
                LOGGER.warn("Tentativa Pix sem identificador local válido ignorada na recuperação.");
                return;
            }
            pixSemIdentificador.add(new PixRecuperacao(conta, pagamento.getId()));
        }
    }

    private void recuperarPixSemIdentificador(Set<PixRecuperacao> tentativas) {
        int identificadas = 0;
        int naoIdentificadas = 0;
        int ativadas = 0;
        int falhas = 0;

        for (PixRecuperacao tentativa : tentativas) {
            ContaConciliacao conta = tentativa.conta();
            try {
                var resultado = pagamentoService.consultarCobrancaPix(
                        conta.tipo(), conta.id(), tentativa.pagamentoId());

                Object identificador = resultado.get("mercadoPagoPagamentoId");
                if (identificador instanceof String id && id.matches("[0-9]+")) {
                    identificadas++;
                    if ("APROVADO".equals(resultado.get("status"))
                            && Boolean.TRUE.equals(resultado.get("planoAtivado"))) {
                        ativadas++;
                    }
                } else if (Boolean.TRUE.equals(resultado.get("buscaReferenciaRealizada"))
                        && Boolean.TRUE.equals(resultado.get("requerConciliacao"))) {
                    naoIdentificadas++;
                } else {
                    falhas++;
                    LOGGER.warn("Resultado inválido ao recuperar Pix {} da conta {}:{}",
                            tentativa.pagamentoId(), conta.tipo(), conta.id());
                }
            } catch (RuntimeException e) {
                falhas++;
                LOGGER.warn("Falha ao recuperar Pix {} da conta {}:{}: {}",
                        tentativa.pagamentoId(), conta.tipo(), conta.id(), e.getClass().getSimpleName());
            }
        }

        if (!tentativas.isEmpty()) {
            LOGGER.info("Recuperação Pix: {} tentativas, {} identificadas, {} ainda sem identificação, {} com plano ativado, {} falhas",
                    tentativas.size(), identificadas, naoIdentificadas, ativadas, falhas);
        }
    }

    private ContaConciliacao identificarConta(Long empresaId, Long entregadorId) {
        if (empresaId != null && empresaId > 0 && entregadorId == null) {
            return new ContaConciliacao(Assinatura.TipoConta.EMPRESA, empresaId);
        }
        if (entregadorId != null && entregadorId > 0 && empresaId == null) {
            return new ContaConciliacao(Assinatura.TipoConta.ENTREGADOR, entregadorId);
        }
        LOGGER.warn("Registro financeiro com titularidade inválida ignorado na conciliação.");
        return null;
    }

    private record ContaConciliacao(Assinatura.TipoConta tipo, Long id) {}

    private record PixRecuperacao(ContaConciliacao conta, Long pagamentoId) {}
}
