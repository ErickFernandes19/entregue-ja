package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;

@Service
public class AssinaturaService {

    private static final ZoneId FUSO = ZoneId.of("America/Sao_Paulo");
    private static final int DIAS_TESTE = 14;
    private static final int DIAS_PLANO_PAGO = 30;

    private final AssinaturaRepository assinaturaRepository;
    private final UsuarioRepository usuarioRepository;
    private final EmpresaRepository empresaRepository;
    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final EntityManager entityManager;

    public AssinaturaService(
            AssinaturaRepository assinaturaRepository,
            UsuarioRepository usuarioRepository,
            EmpresaRepository empresaRepository,
            PagamentoAssinaturaRepository pagamentoRepository,
            EntityManager entityManager
    ) {
        this.assinaturaRepository = assinaturaRepository;
        this.usuarioRepository = usuarioRepository;
        this.empresaRepository = empresaRepository;
        this.pagamentoRepository = pagamentoRepository;
        this.entityManager = entityManager;
    }

    @Transactional(readOnly = true)
    public Optional<Assinatura> buscarAtiva(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        return assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                tipoConta, contaId, Assinatura.Status.ATIVA
        ).filter(assinatura -> !estaVencida(assinatura, LocalDateTime.now(FUSO)));
    }

    @Transactional(readOnly = true)
    public List<Assinatura> listarHistorico(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        return assinaturaRepository.findByTipoContaAndContaIdOrderByIdDesc(tipoConta, contaId);
    }

    @Transactional
    public Assinatura obterOuCriarGratuita(Assinatura.TipoConta tipoConta, Long contaId) {
        validarIdentificadores(tipoConta, contaId);
        bloquearConta(tipoConta, contaId);
        LocalDateTime agora = LocalDateTime.now(FUSO);
        Optional<Assinatura> ativa = assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                tipoConta, contaId, Assinatura.Status.ATIVA
        );
        if (ativa.isPresent()) {
            Assinatura assinatura = ativa.get();
            if (!estaVencida(assinatura, agora)) return assinatura;
            assinatura.setStatus(Assinatura.Status.EXPIRADA);
            assinatura.setRenovacaoAutomatica(false);
            assinaturaRepository.save(assinatura);
        }
        return criarGratuita(tipoConta, contaId, agora);
    }

    @Transactional
    public Assinatura iniciarTesteEssencial(Long empresaId) {
        validarIdentificadores(Assinatura.TipoConta.EMPRESA, empresaId);
        bloquearConta(Assinatura.TipoConta.EMPRESA, empresaId);
        boolean jaUtilizouTeste = assinaturaRepository.existsByTipoContaAndContaIdAndTesteGratuitoTrue(
                Assinatura.TipoConta.EMPRESA, empresaId
        );
        if (jaUtilizouTeste) throw new IllegalStateException("Esta empresa já utilizou o teste gratuito.");
        LocalDateTime agora = LocalDateTime.now(FUSO);
        Optional<Assinatura> ativa = assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, empresaId, Assinatura.Status.ATIVA
        );
        if (ativa.isPresent()) {
            Assinatura atual = ativa.get();
            if (estaVencida(atual, agora)) {
                atual.setStatus(Assinatura.Status.EXPIRADA);
                atual.setRenovacaoAutomatica(false);
            } else if (atual.getPlano() != Assinatura.Plano.GRATUITO) {
                throw new IllegalStateException("O teste gratuito está disponível apenas para empresas no plano Gratuito.");
            } else {
                atual.setStatus(Assinatura.Status.CANCELADA);
                atual.setRenovacaoAutomatica(false);
            }
            assinaturaRepository.save(atual);
        }
        Assinatura teste = new Assinatura();
        teste.setTipoConta(Assinatura.TipoConta.EMPRESA);
        teste.setContaId(empresaId);
        teste.setPlano(Assinatura.Plano.ESSENCIAL);
        teste.setStatus(Assinatura.Status.ATIVA);
        teste.setTesteGratuito(true);
        teste.setDataInicio(agora);
        teste.setDataVencimento(agora.plusDays(DIAS_TESTE));
        teste.setRenovacaoAutomatica(false);
        return assinaturaRepository.save(teste);
    }

    @Transactional
    public Assinatura agendarTrocaPlano(Long empresaId, Assinatura.Plano novoPlano) {
        validarIdentificadores(Assinatura.TipoConta.EMPRESA, empresaId);
        if (novoPlano != Assinatura.Plano.ESSENCIAL
                && novoPlano != Assinatura.Plano.PROFISSIONAL) {
            throw new IllegalArgumentException("Selecione um plano pago válido.");
        }

        bloquearConta(Assinatura.TipoConta.EMPRESA, empresaId);
        LocalDateTime agora = LocalDateTime.now(FUSO);
        Assinatura atual = assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, empresaId, Assinatura.Status.ATIVA
        ).orElseThrow(() -> new IllegalStateException("Não existe assinatura ativa para agendar a troca."));

        if (estaVencida(atual, agora) || atual.isTesteGratuito()
                || atual.getPlano() == Assinatura.Plano.GRATUITO
                || atual.getDataVencimento() == null) {
            throw new IllegalStateException("A troca programada exige um plano pago vigente.");
        }
        if (atual.getPlano() == novoPlano) {
            throw new IllegalArgumentException("O plano solicitado já está ativo.");
        }

        atual.setPlanoAgendado(novoPlano);
        atual.setDataTrocaAgendada(atual.getDataVencimento());
        return assinaturaRepository.save(atual);
    }

    @Transactional
    public Assinatura cancelarTrocaAgendada(Long empresaId) {
        validarIdentificadores(Assinatura.TipoConta.EMPRESA, empresaId);
        bloquearConta(Assinatura.TipoConta.EMPRESA, empresaId);
        Assinatura atual = assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, empresaId, Assinatura.Status.ATIVA
        ).orElseThrow(() -> new IllegalStateException("Não existe assinatura ativa."));
        atual.setPlanoAgendado(null);
        atual.setDataTrocaAgendada(null);
        return assinaturaRepository.save(atual);
    }

    @Transactional
    public Assinatura ativarPlanoPagoPorPix(Long empresaId, Long pagamentoId) {
        return ativarPlanoPago(empresaId, pagamentoId, PagamentoAssinatura.FormaPagamento.PIX);
    }

    @Transactional
    public Assinatura ativarPlanoPagoPorCartao(Long empresaId, Long pagamentoId) {
        return ativarPlanoPago(empresaId, pagamentoId, PagamentoAssinatura.FormaPagamento.CARTAO);
    }

    private Assinatura ativarPlanoPago(
            Long empresaId,
            Long pagamentoId,
            PagamentoAssinatura.FormaPagamento formaPagamento
    ) {
        validarIdentificadores(Assinatura.TipoConta.EMPRESA, empresaId);
        if (pagamentoId == null || pagamentoId <= 0) {
            throw new IllegalArgumentException("Pagamento inválido.");
        }

        bloquearConta(Assinatura.TipoConta.EMPRESA, empresaId);

        PagamentoAssinatura pagamento = pagamentoRepository.buscarPorIdComBloqueio(pagamentoId)
                .orElseThrow(() -> new IllegalArgumentException("Pagamento não encontrado."));

        if (!empresaId.equals(pagamento.getEmpresaId()) || pagamento.getFormaPagamento() != formaPagamento) {
            throw new IllegalArgumentException("Pagamento não pertence à empresa ou possui forma inválida.");
        }

        if (pagamento.getStatus() != PagamentoAssinatura.Status.APROVADO
                || pagamento.getDataAprovacao() == null
                || pagamento.getMercadoPagoPagamentoId() == null
                || !pagamento.getMercadoPagoPagamentoId().matches("[0-9]+")) {
            throw new IllegalStateException("O pagamento ainda não foi confirmado.");
        }

        if (formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO
                && (pagamento.getMercadoPagoAssinaturaId() == null
                || !pagamento.getMercadoPagoAssinaturaId().matches("[A-Za-z0-9_-]{1,100}"))) {
            throw new IllegalStateException("O pagamento não possui assinatura recorrente válida.");
        }

        BigDecimal esperado = switch (pagamento.getPlano()) {
            case ESSENCIAL -> new BigDecimal("39.90");
            case PROFISSIONAL -> new BigDecimal("79.90");
            default -> throw new IllegalArgumentException("Plano inválido para pagamento.");
        };

        if (pagamento.getValor() == null || pagamento.getValor().compareTo(esperado) != 0) {
            throw new IllegalStateException("Valor do pagamento inconsistente.");
        }

        LocalDateTime agora = LocalDateTime.now(FUSO);
        Optional<Assinatura> ativa = assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, empresaId, Assinatura.Status.ATIVA
        );

        if (pagamento.getDataVencimento() != null) {
            return ativa.filter(a -> !estaVencida(a, agora)
                            && a.getPlano() == pagamento.getPlano()
                            && !a.isTesteGratuito()
                            && a.getDataVencimento() != null
                            && !a.getDataVencimento().isBefore(pagamento.getDataVencimento()))
                    .orElseThrow(() -> new IllegalStateException(
                            "Este pagamento já foi utilizado e não pode renovar o plano novamente."
                    ));
        }

        if (ativa.isPresent()) {
            Assinatura atual = ativa.get();

            if (!estaVencida(atual, agora) && !atual.isTesteGratuito()
                    && atual.getPlano() != Assinatura.Plano.GRATUITO) {
                if (atual.getPlanoAgendado() != null) {
                    throw new IllegalStateException(
                            "Existe uma troca programada. Aguarde o vencimento antes de ativar uma nova mensalidade."
                    );
                }
                if (atual.getPlano() != pagamento.getPlano()) {
                    throw new IllegalStateException(
                            "A troca de plano somente pode ser aplicada após o vencimento atual."
                    );
                }
            }

            if (estaVencida(atual, agora) && atual.getPlanoAgendado() != null
                    && atual.getPlanoAgendado() != pagamento.getPlano()) {
                throw new IllegalStateException(
                        "O pagamento não corresponde ao plano agendado para o próximo ciclo."
                );
            }

            if (!estaVencida(atual, agora) && atual.isRenovacaoAutomatica()) {
                if (formaPagamento != PagamentoAssinatura.FormaPagamento.CARTAO
                        || !pagamento.getMercadoPagoAssinaturaId().equals(atual.getMercadoPagoAssinaturaId())) {
                    throw new IllegalStateException(
                            "Existe uma assinatura recorrente ativa diferente. Cancele a renovação anterior antes de alterar a cobrança."
                    );
                }
            }

            if (!estaVencida(atual, agora)
                    && formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO
                    && atual.getMercadoPagoAssinaturaId() != null
                    && !atual.getMercadoPagoAssinaturaId().equals(pagamento.getMercadoPagoAssinaturaId())) {
                throw new IllegalStateException("A cobrança pertence a outra assinatura recorrente.");
            }

            if (!estaVencida(atual, agora)
                    && !atual.isTesteGratuito()
                    && atual.getPlano() == pagamento.getPlano()
                    && atual.getDataVencimento() != null) {
                LocalDateTime novoVencimento = atual.getDataVencimento().plusDays(DIAS_PLANO_PAGO);
                atual.setDataVencimento(novoVencimento);
                atual.setRenovacaoAutomatica(formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO);
                atual.setMercadoPagoAssinaturaId(formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO
                        ? pagamento.getMercadoPagoAssinaturaId() : null);
                Assinatura renovada = assinaturaRepository.save(atual);
                pagamento.setDataVencimento(novoVencimento);
                pagamentoRepository.save(pagamento);
                return renovada;
            }

            atual.setStatus(estaVencida(atual, agora)
                    ? Assinatura.Status.EXPIRADA
                    : Assinatura.Status.CANCELADA);
            atual.setRenovacaoAutomatica(false);
            assinaturaRepository.save(atual);
        }

        Assinatura nova = new Assinatura();
        nova.setTipoConta(Assinatura.TipoConta.EMPRESA);
        nova.setContaId(empresaId);
        nova.setPlano(pagamento.getPlano());
        nova.setStatus(Assinatura.Status.ATIVA);
        nova.setTesteGratuito(false);
        nova.setDataInicio(agora);
        nova.setDataVencimento(agora.plusDays(DIAS_PLANO_PAGO));
        nova.setRenovacaoAutomatica(formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO);
        if (formaPagamento == PagamentoAssinatura.FormaPagamento.CARTAO) {
            nova.setMercadoPagoAssinaturaId(pagamento.getMercadoPagoAssinaturaId());
        }

        Assinatura salva = assinaturaRepository.save(nova);
        pagamento.setDataVencimento(salva.getDataVencimento());
        pagamentoRepository.save(pagamento);
        return salva;
    }

    private boolean estaVencida(Assinatura assinatura, LocalDateTime agora) {
        LocalDateTime vencimento = assinatura.getDataVencimento();
        return vencimento != null && !vencimento.isAfter(agora);
    }

    private Assinatura criarGratuita(Assinatura.TipoConta tipoConta, Long contaId, LocalDateTime agora) {
        Assinatura assinatura = new Assinatura();
        assinatura.setTipoConta(tipoConta);
        assinatura.setContaId(contaId);
        assinatura.setPlano(Assinatura.Plano.GRATUITO);
        assinatura.setStatus(Assinatura.Status.ATIVA);
        assinatura.setTesteGratuito(false);
        assinatura.setDataInicio(agora);
        assinatura.setDataVencimento(null);
        assinatura.setRenovacaoAutomatica(false);
        return assinaturaRepository.save(assinatura);
    }

    private void bloquearConta(Assinatura.TipoConta tipoConta, Long contaId) {
        Object conta = switch (tipoConta) {
            case ENTREGADOR -> entityManager.find(Usuario.class, contaId, LockModeType.PESSIMISTIC_WRITE);
            case EMPRESA -> entityManager.find(Empresa.class, contaId, LockModeType.PESSIMISTIC_WRITE);
        };
        if (conta == null) throw new IllegalArgumentException("Conta não encontrada.");
    }

    private void validarConta(Assinatura.TipoConta tipoConta, Long contaId) {
        validarIdentificadores(tipoConta, contaId);
        boolean existe = switch (tipoConta) {
            case ENTREGADOR -> usuarioRepository.existsById(contaId);
            case EMPRESA -> empresaRepository.existsById(contaId);
        };
        if (!existe) throw new IllegalArgumentException("Conta não encontrada.");
    }

    private void validarIdentificadores(Assinatura.TipoConta tipoConta, Long contaId) {
        if (tipoConta == null) throw new IllegalArgumentException("Tipo de conta é obrigatório.");
        if (contaId == null || contaId <= 0) throw new IllegalArgumentException("Identificador da conta é inválido.");
    }
}