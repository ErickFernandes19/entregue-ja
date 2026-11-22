package com.entregueja.backend.service;

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
    private final AtomicBoolean executando = new AtomicBoolean(false);

    public ConciliacaoPagamentosScheduler(
            PagamentoAssinaturaRepository pagamentoRepository,
            AssinaturaRecorrenteRepository recorrenteRepository,
            AssinaturaRecorrenteService assinaturaRecorrenteService
    ) {
        this.pagamentoRepository = pagamentoRepository;
        this.recorrenteRepository = recorrenteRepository;
        this.assinaturaRecorrenteService = assinaturaRecorrenteService;
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
            Set<Long> empresas = new LinkedHashSet<>();

            for (PagamentoAssinatura pagamento : pagamentoRepository.findByStatusOrderByDataCriacaoAsc(
                    PagamentoAssinatura.Status.PENDENTE)) {
                adicionarEmpresa(empresas, pagamento.getEmpresaId());
            }

            for (PagamentoAssinatura pagamento : pagamentoRepository.findByStatusOrderByDataCriacaoAsc(
                    PagamentoAssinatura.Status.APROVADO)) {
                if (pagamento.getDataVencimento() == null) {
                    adicionarEmpresa(empresas, pagamento.getEmpresaId());
                }
            }

            for (AssinaturaRecorrente recorrente : recorrenteRepository.findAll()) {
                if (recorrente.getMercadoPagoAssinaturaId() != null
                        && !recorrente.getMercadoPagoAssinaturaId().isBlank()) {
                    adicionarEmpresa(empresas, recorrente.getEmpresaId());
                }
            }

            int sucesso = 0;
            int falhas = 0;

            for (Long empresaId : empresas) {
                try {
                    var resultado = assinaturaRecorrenteService.conciliarPagamentos(empresaId);
                    Object falhasInternas = resultado.get("falhas");
                    if (falhasInternas instanceof Number numero && numero.intValue() > 0) {
                        falhas++;
                        LOGGER.warn("Conciliação da empresa {} retornou {} falhas internas", empresaId, numero);
                    } else {
                        sucesso++;
                    }
                } catch (Exception e) {
                    falhas++;
                    LOGGER.error("Falha ao conciliar pagamentos da empresa {}", empresaId, e);
                }
            }

            if (!empresas.isEmpty()) {
                LOGGER.info("Conciliação concluída: {} empresas, {} sem falhas, {} com falha",
                        empresas.size(), sucesso, falhas);
            }
        } catch (Exception e) {
            LOGGER.error("Falha ao executar a conciliação automática de pagamentos", e);
        } finally {
            executando.set(false);
        }
    }

    private void adicionarEmpresa(Set<Long> empresas, Long empresaId) {
        if (empresaId != null && empresaId > 0) {
            empresas.add(empresaId);
        }
    }
}
