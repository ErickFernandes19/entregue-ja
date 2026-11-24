package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.MissingNode;
import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class PagamentoAssinaturaService {

    private static final ZoneId FUSO = ZoneId.of("America/Sao_Paulo");

    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final AssinaturaRecorrenteRepository recorrenteRepository;
    private final MercadoPagoService mercadoPagoService;
    private final AssinaturaService assinaturaService;
    private final EntityManager entityManager;
    private final TransactionTemplate transacaoPix;

    private record TentativaPix(Long id, String email, String chave, boolean nova) {}

    public PagamentoAssinaturaService(
            PagamentoAssinaturaRepository pagamentoRepository,
            AssinaturaRecorrenteRepository recorrenteRepository,
            MercadoPagoService mercadoPagoService,
            AssinaturaService assinaturaService,
            EntityManager entityManager,
            PlatformTransactionManager transactionManager
    ) {
        this.pagamentoRepository = pagamentoRepository;
        this.recorrenteRepository = recorrenteRepository;
        this.mercadoPagoService = mercadoPagoService;
        this.assinaturaService = assinaturaService;
        this.entityManager = entityManager;
        this.transacaoPix = new TransactionTemplate(transactionManager);
        this.transacaoPix.setPropagationBehavior(Propagation.REQUIRES_NEW.value());
    }

    @Transactional(propagation = Propagation.NEVER)
    public Map<String, Object> criarCobrancaPix(Long empresaId, Assinatura.Plano plano, String chaveIdempotencia) {
        return criarCobrancaPix(Assinatura.TipoConta.EMPRESA, empresaId, plano, chaveIdempotencia);
    }

    @Transactional(propagation = Propagation.NEVER)
    public Map<String, Object> criarCobrancaPix(
            Assinatura.TipoConta tipoConta, Long contaId, Assinatura.Plano plano, String chaveIdempotencia) {
        BigDecimal valor = AssinaturaService.valorDoPlano(tipoConta, plano);
        validarChave(chaveIdempotencia);

        TentativaPix tentativa = transacaoPix.execute(status -> {
            bloquearConta(tipoConta, contaId);
            String email = obterEmailConta(tipoConta, contaId);
            PagamentoAssinatura existente = pagamentoRepository.findByChaveIdempotencia(chaveIdempotencia)
                    .orElse(null);
            if (existente != null) {
                validarVinculoTentativaPix(existente, tipoConta, contaId, plano, valor, chaveIdempotencia);
                return new TentativaPix(existente.getId(), email, existente.getChaveIdempotencia(), false);
            }
            validarContratacaoPix(tipoConta, contaId, plano);
            validarCobrancasEmAberto(tipoConta, contaId, null);
            PagamentoAssinatura novo = registrarPagamento(tipoConta, contaId, plano, valor, chaveIdempotencia);
            if (novo.getId() == null || novo.getId() <= 0) {
                throw new IllegalStateException("Não foi possível registrar a tentativa de pagamento.");
            }
            return new TentativaPix(novo.getId(), email, novo.getChaveIdempotencia(), true);
        });

        if (tentativa == null || tentativa.id() == null || tentativa.id() <= 0) {
            throw new IllegalStateException("Tentativa de pagamento inválida.");
        }

        if (!tentativa.nova()) {
            return transacaoPix.execute(status -> consultarCobrancaPix(tipoConta, contaId, tentativa.id()));
        }

        JsonNode respostaExterna = mercadoPagoService.criarPagamentoPix(
                valor,
                "Assinatura Entregue Já - " + plano.name(),
                tentativa.email(),
                "entregueja-pagamento-" + tentativa.id(),
                tentativa.chave()
        );

        String idExterno = texto(respostaExterna, "id");
        if (idExterno == null || !idExterno.matches("[0-9]{1,100}")) {
            throw new IllegalStateException("O Mercado Pago não retornou um identificador válido.");
        }

        JsonNode respostaConfirmada = transacaoPix.execute(status -> {
            bloquearConta(tipoConta, contaId);
            PagamentoAssinatura pagamento = obterTentativaPix(tipoConta, contaId, plano, valor, tentativa);
            String idRegistrado = pagamento.getMercadoPagoPagamentoId();
            JsonNode resposta = respostaExterna;
            if (idRegistrado != null && !idRegistrado.isBlank()) {
                if (!idExterno.equals(idRegistrado)) {
                    throw new IllegalStateException("A tentativa já está vinculada a outro pagamento.");
                }
                resposta = mercadoPagoService.consultarPagamento(idRegistrado);
            } else {
                validarIdentificadorDisponivel(pagamento, idExterno);
                pagamento.setMercadoPagoPagamentoId(idExterno);
            }
            registrarStatusPix(pagamento, resposta);
            return resposta;
        });

        return transacaoPix.execute(status -> {
            bloquearConta(tipoConta, contaId);
            PagamentoAssinatura pagamento = obterTentativaPix(tipoConta, contaId, plano, valor, tentativa);
            if (!idExterno.equals(pagamento.getMercadoPagoPagamentoId())) {
                throw new IllegalStateException("Identificador da tentativa de pagamento inconsistente.");
            }
            ativarPixAprovado(pagamento);
            return montarResposta(pagamento, respostaConfirmada);
        });
    }

    private PagamentoAssinatura obterTentativaPix(
            Assinatura.TipoConta tipoConta, Long contaId, Assinatura.Plano plano,
            BigDecimal valor, TentativaPix tentativa) {
        PagamentoAssinatura pagamento = pagamentoRepository.buscarPorIdComBloqueio(tentativa.id())
                .orElseThrow(() -> new IllegalStateException("Tentativa de pagamento não encontrada."));
        validarVinculoTentativaPix(pagamento, tipoConta, contaId, plano, valor, tentativa.chave());
        return pagamento;
    }

    private void validarVinculoTentativaPix(
            PagamentoAssinatura pagamento, Assinatura.TipoConta tipoConta, Long contaId,
            Assinatura.Plano plano, BigDecimal valor, String chave) {
        if (!pertenceAoTitular(pagamento, tipoConta, contaId)
                || pagamento.getPlano() != plano
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX
                || pagamento.getValor() == null || pagamento.getValor().compareTo(valor) != 0
                || !chave.equals(pagamento.getChaveIdempotencia())) {
            throw new IllegalArgumentException("A chave de idempotência já pertence a outra cobrança.");
        }
    }

    private void validarIdentificadorDisponivel(PagamentoAssinatura pagamento, String idExterno) {
        pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio(idExterno).ifPresent(vinculado -> {
            if (!pagamento.getId().equals(vinculado.getId())
                    || !pertenceAoTitular(vinculado, pagamento.getTipoConta(), pagamento.getContaId())
                    || vinculado.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX) {
                throw new IllegalStateException("O pagamento recuperado já está vinculado a outra cobrança.");
            }
        });
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listarCobrancasPixPendentes(Long empresaId) {
        return listarCobrancasPixPendentes(Assinatura.TipoConta.EMPRESA, empresaId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listarCobrancasPixPendentes(
            Assinatura.TipoConta tipoConta, Long contaId) {
        obterEmailConta(tipoConta, contaId);
        List<PagamentoAssinatura> pagamentos = switch (tipoConta) {
            case EMPRESA -> pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(contaId);
            case ENTREGADOR -> pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(contaId);
        };

        List<Map<String, Object>> resultado = new ArrayList<>();
        for (PagamentoAssinatura pagamento : pagamentos) {
            if (!pertenceAoTitular(pagamento, tipoConta, contaId)) {
                throw new IllegalStateException("Pagamento com titularidade inconsistente.");
            }
            if (pixNaoResolvido(pagamento)) {
                resultado.add(montarResposta(pagamento, MissingNode.getInstance()));
            }
        }
        return resultado;
    }

    private boolean pixNaoResolvido(PagamentoAssinatura pagamento) {
        return pagamento.getFormaPagamento() == PagamentoAssinatura.FormaPagamento.PIX
                && (pagamento.getStatus() == PagamentoAssinatura.Status.PENDENTE
                || pagamento.getStatus() == PagamentoAssinatura.Status.APROVADO
                && pagamento.getDataVencimento() == null);
    }

    @Transactional
    public Map<String, Object> consultarCobrancaPix(Long empresaId, Long pagamentoId) {
        return consultarCobrancaPix(Assinatura.TipoConta.EMPRESA, empresaId, pagamentoId);
    }

    @Transactional
    public Map<String, Object> consultarCobrancaPix(
            Assinatura.TipoConta tipoConta, Long contaId, Long pagamentoId) {
        bloquearConta(tipoConta, contaId);
        obterEmailConta(tipoConta, contaId);
        if (pagamentoId == null || pagamentoId <= 0) {
            throw new IllegalArgumentException("Pagamento não encontrado.");
        }
        PagamentoAssinatura pagamento = pagamentoRepository.buscarPorIdComBloqueio(pagamentoId)
                .orElseThrow(() -> new IllegalArgumentException("Pagamento não encontrado."));

        if (!pertenceAoTitular(pagamento, tipoConta, contaId)
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX) {
            throw new IllegalArgumentException("Pagamento não encontrado.");
        }

        if (pagamento.getMercadoPagoPagamentoId() == null
                || pagamento.getMercadoPagoPagamentoId().isBlank()) {
            if (!pixNaoResolvido(pagamento)) {
                throw new IllegalStateException("A cobrança ainda não possui identificador externo.");
            }
            return recuperarPixPorReferencia(pagamento);
        }

        JsonNode resposta = mercadoPagoService.consultarPagamento(pagamento.getMercadoPagoPagamentoId());
        atualizarStatusEAtivar(pagamento, resposta);
        return montarResposta(pagamento, resposta);
    }


    private Map<String, Object> recuperarPixPorReferencia(PagamentoAssinatura pagamento) {
        if (pagamento.getId() == null || pagamento.getId() <= 0 || !pixNaoResolvido(pagamento)) {
            throw new IllegalStateException("Cobrança inválida para recuperação.");
        }
        BigDecimal valorEsperado = AssinaturaService.valorDoPlano(pagamento.getTipoConta(), pagamento.getPlano());
        if (pagamento.getValor() == null || pagamento.getValor().compareTo(valorEsperado) != 0) {
            throw new IllegalStateException("Valor da cobrança local inconsistente.");
        }

        String referencia = "entregueja-pagamento-" + pagamento.getId();
        var encontrado = mercadoPagoService.buscarPagamentoPixPorReferencia(referencia, pagamento.getValor());
        if (encontrado.isEmpty()) {
            Map<String, Object> resultado = montarResposta(pagamento, MissingNode.getInstance());
            resultado.put("buscaReferenciaRealizada", true);
            return resultado;
        }

        JsonNode resposta = encontrado.get();
        String idExterno = texto(resposta, "id");
        if (idExterno == null || !idExterno.matches("[0-9]+")) {
            throw new IllegalStateException("Identificador do pagamento recuperado inválido.");
        }
        validarIdentificadorDisponivel(pagamento, idExterno);

        pagamento.setMercadoPagoPagamentoId(idExterno);
        atualizarStatusEAtivar(pagamento, resposta);
        Map<String, Object> resultado = montarResposta(pagamento, resposta);
        resultado.put("buscaReferenciaRealizada", true);
        return resultado;
    }

    @Transactional
    public Map<String, Object> processarPagamentoRecorrente(String mercadoPagoPagamentoId) {
        return processarPagamentoRecorrente(mercadoPagoPagamentoId, null);
    }

    private Map<String, Object> processarPagamentoRecorrente(
            String mercadoPagoPagamentoId, String assinaturaConfirmadaNaListagem) {
        if (mercadoPagoPagamentoId == null || !mercadoPagoPagamentoId.matches("[0-9]+")) {
            throw new IllegalArgumentException("Identificador do pagamento inválido.");
        }

        JsonNode externo = mercadoPagoService.consultarPagamentoRecorrente(mercadoPagoPagamentoId);
        if (!mercadoPagoPagamentoId.equals(texto(externo, "id"))) {
            throw new IllegalStateException("Identificador externo do pagamento inconsistente.");
        }

        String assinaturaExterna = texto(externo, "preapproval_id");
        if (assinaturaExterna == null) {
            assinaturaExterna = texto(externo.path("metadata"), "preapproval_id");
        }
        if (assinaturaConfirmadaNaListagem != null) {
            if (assinaturaExterna != null && !assinaturaConfirmadaNaListagem.equals(assinaturaExterna)) {
                throw new IllegalStateException("A cobrança diverge da assinatura informada na listagem autorizada.");
            }
            assinaturaExterna = assinaturaConfirmadaNaListagem;
        }
        if (assinaturaExterna == null) {
            throw new IllegalStateException("Não foi possível comprovar a assinatura recorrente vinculada à cobrança.");
        }

        final String idAssinaturaExterna = assinaturaExterna;
        AssinaturaRecorrente recorrente = recorrenteRepository
                .findByMercadoPagoAssinaturaId(assinaturaExterna)
                .orElseThrow(() -> new IllegalStateException("Assinatura recorrente não encontrada."));

        Assinatura.TipoConta tipoConta = recorrente.getTipoConta();
        Long contaId = recorrente.getContaId();
        Long idBloqueado = bloquearConta(tipoConta, contaId);
        if (!contaId.equals(idBloqueado)) {
            throw new IllegalStateException("Conta inválida.");
        }

        validarTrocaProgramada(recorrente);
        if (recorrente.getValor() == null || recorrente.getValor().compareTo(
                AssinaturaService.valorDoPlano(tipoConta, recorrente.getPlano())) != 0) {
            throw new IllegalStateException("Valor do plano recorrente inconsistente.");
        }

        JsonNode assinaturaMercadoPago = mercadoPagoService.consultarAssinaturaRecorrente(assinaturaExterna);
        if (!assinaturaExterna.equals(texto(assinaturaMercadoPago, "id"))
                || !("entregueja-recorrente-" + recorrente.getId()).equals(texto(assinaturaMercadoPago, "external_reference"))) {
            throw new IllegalStateException("Identidade da assinatura recorrente inconsistente.");
        }
        JsonNode valorAssinatura = assinaturaMercadoPago.path("auto_recurring").path("transaction_amount");
        String moedaAssinatura = texto(assinaturaMercadoPago.path("auto_recurring"), "currency_id");
        if (!valorAssinatura.isNumber() || valorAssinatura.decimalValue().compareTo(recorrente.getValor()) != 0
                || !"BRL".equals(moedaAssinatura)) {
            throw new IllegalStateException("Valor ou moeda da assinatura recorrente inconsistente.");
        }

        JsonNode valorExterno = externo.path("transaction_amount");
        if (!valorExterno.isNumber() || valorExterno.decimalValue().compareTo(recorrente.getValor()) != 0) {
            throw new IllegalStateException("Valor da cobrança recorrente inconsistente.");
        }
        if (!"BRL".equals(texto(externo, "currency_id"))) {
            throw new IllegalStateException("Moeda da cobrança recorrente inconsistente.");
        }
        String tipoPagamentoExterno = texto(externo, "payment_type_id");
        if (!"credit_card".equals(tipoPagamentoExterno) && !"account_money".equals(tipoPagamentoExterno)) {
            throw new IllegalStateException("Tipo de pagamento da cobrança recorrente não permitido.");
        }

        String statusExterno = texto(externo, "status");
        if (statusExterno == null) {
            throw new IllegalStateException("Status externo não informado.");
        }
        PagamentoAssinatura.Status status = switch (statusExterno) {
            case "approved" -> PagamentoAssinatura.Status.APROVADO;
            case "rejected" -> PagamentoAssinatura.Status.RECUSADO;
            case "cancelled" -> PagamentoAssinatura.Status.CANCELADO;
            case "refunded", "charged_back" -> PagamentoAssinatura.Status.REEMBOLSADO;
            default -> PagamentoAssinatura.Status.PENDENTE;
        };

        PagamentoAssinatura pagamento = pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio(mercadoPagoPagamentoId)
                .orElseGet(() -> {
                    PagamentoAssinatura novo = new PagamentoAssinatura();
                    atribuirTitular(novo, tipoConta, contaId);
                    novo.setPlano(recorrente.getPlano());
                    novo.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
                    novo.setValor(recorrente.getValor());
                    novo.setStatus(PagamentoAssinatura.Status.PENDENTE);
                    novo.setMercadoPagoPagamentoId(mercadoPagoPagamentoId);
                    novo.setMercadoPagoAssinaturaId(idAssinaturaExterna);
                    novo.setChaveIdempotencia(UUID.nameUUIDFromBytes(
                            ("entregueja-recorrente-pagamento-" + mercadoPagoPagamentoId)
                                    .getBytes(StandardCharsets.UTF_8)).toString());
                    return pagamentoRepository.saveAndFlush(novo);
                });

        if (!pertenceAoTitular(pagamento, tipoConta, contaId)
                || pagamento.getPlano() != recorrente.getPlano()
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.CARTAO
                || !assinaturaExterna.equals(pagamento.getMercadoPagoAssinaturaId())
                || pagamento.getValor() == null
                || pagamento.getValor().compareTo(recorrente.getValor()) != 0) {
            throw new IllegalStateException("Cobrança já vinculada a outra assinatura.");
        }

        validarTransicaoStatus(pagamento, status);
        pagamento.setStatus(status);
        if (status == PagamentoAssinatura.Status.APROVADO && pagamento.getDataAprovacao() == null) {
            pagamento.setDataAprovacao(LocalDateTime.now(FUSO));
        }
        pagamentoRepository.saveAndFlush(pagamento);

        if (status == PagamentoAssinatura.Status.APROVADO && pagamento.getDataVencimento() == null) {
            if (tipoConta == Assinatura.TipoConta.EMPRESA) {
                assinaturaService.ativarPlanoPagoPorCartao(contaId, pagamento.getId());
            } else {
                assinaturaService.ativarPlanoPagoPorCartao(tipoConta, contaId, pagamento.getId());
            }
        }

        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("pagamentoId", pagamento.getId());
        resultado.put("mercadoPagoPagamentoId", mercadoPagoPagamentoId);
        resultado.put("assinaturaRecorrenteId", recorrente.getId());
        resultado.put("status", pagamento.getStatus().name());
        resultado.put("planoAtivado", pagamento.getDataVencimento() != null);
        resultado.put("vencimentoPlano", pagamento.getDataVencimento());
        return resultado;
    }

    @Transactional
    public Map<String, Object> recuperarMensalidadesRecorrentes(Long empresaId) {
        return recuperarMensalidadesRecorrentes(Assinatura.TipoConta.EMPRESA, empresaId);
    }

    @Transactional
    public Map<String, Object> recuperarMensalidadesRecorrentes(
            Assinatura.TipoConta tipoConta, Long contaId) {
        bloquearConta(tipoConta, contaId);

        int assinaturasConsultadas = 0;
        int mensalidadesEncontradas = 0;
        int mensalidadesProcessadas = 0;
        int mensalidadesJaRegistradas = 0;

        List<AssinaturaRecorrente> recorrentes = switch (tipoConta) {
            case EMPRESA -> recorrenteRepository.findByEmpresaIdOrderByIdDesc(contaId);
            case ENTREGADOR -> recorrenteRepository.findByEntregadorIdOrderByIdDesc(contaId);
        };
        for (AssinaturaRecorrente recorrente : recorrentes) {
            if (recorrente.getTipoConta() != tipoConta || !contaId.equals(recorrente.getContaId())) {
                throw new IllegalStateException("Assinatura recorrente vinculada a outra conta.");
            }
            String assinaturaExterna = recorrente.getMercadoPagoAssinaturaId();
            if (assinaturaExterna == null || assinaturaExterna.isBlank()) {
                continue;
            }

            JsonNode assinatura = mercadoPagoService.consultarAssinaturaRecorrente(assinaturaExterna);
            if (!assinaturaExterna.equals(texto(assinatura, "id"))
                    || !("entregueja-recorrente-" + recorrente.getId())
                    .equals(texto(assinatura, "external_reference"))) {
                throw new IllegalStateException("Identidade da assinatura recorrente inconsistente.");
            }

            assinaturasConsultadas++;
            int deslocamento = 0;
            final int limite = 20;
            final int maximoPaginas = 100;

            for (int pagina = 0; pagina < maximoPaginas; pagina++) {
                JsonNode resultado = mercadoPagoService.listarPagamentosAutorizados(
                        assinaturaExterna, limite, deslocamento);
                JsonNode registros = resultado.path("results");
                if (!registros.isArray()) {
                    throw new IllegalStateException("Listagem de mensalidades inválida.");
                }

                for (JsonNode registro : registros) {
                    String vinculo = texto(registro, "preapproval_id");
                    if (vinculo == null || !assinaturaExterna.equals(vinculo)) {
                        throw new IllegalStateException("Mensalidade vinculada a outra assinatura.");
                    }

                    String pagamentoExterno = texto(registro.path("payment"), "id");
                    if (pagamentoExterno == null || !pagamentoExterno.matches("[0-9]+")) {
                        throw new IllegalStateException("Mensalidade sem identificador de pagamento válido.");
                    }

                    mensalidadesEncontradas++;
                    boolean existente = pagamentoRepository.findByMercadoPagoPagamentoId(pagamentoExterno)
                            .isPresent();
                    processarPagamentoRecorrente(pagamentoExterno, assinaturaExterna);
                    if (existente) {
                        mensalidadesJaRegistradas++;
                    } else {
                        mensalidadesProcessadas++;
                    }
                }

                if (registros.size() < limite) {
                    break;
                }
                deslocamento += limite;
                if (pagina == maximoPaginas - 1) {
                    throw new IllegalStateException("Limite de paginação atingido na conciliação.");
                }
            }
        }

        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("assinaturasConsultadas", assinaturasConsultadas);
        resultado.put("mensalidadesEncontradas", mensalidadesEncontradas);
        resultado.put("mensalidadesRegistradas", mensalidadesProcessadas);
        resultado.put("mensalidadesJaRegistradas", mensalidadesJaRegistradas);
        return resultado;
    }

    private void validarCobrancasEmAberto(
            Assinatura.TipoConta tipoConta, Long contaId, PagamentoAssinatura pagamentoAtual) {
        List<AssinaturaRecorrente.Status> statusAtivos = List.of(
                AssinaturaRecorrente.Status.PENDENTE,
                AssinaturaRecorrente.Status.AUTORIZADA,
                AssinaturaRecorrente.Status.PAUSADA);
        List<AssinaturaRecorrente.EstadoCriacao> estadosIncertos = List.of(
                AssinaturaRecorrente.EstadoCriacao.PREPARADA,
                AssinaturaRecorrente.EstadoCriacao.ENVIANDO,
                AssinaturaRecorrente.EstadoCriacao.INCERTA);

        boolean possuiRecorrente = switch (tipoConta) {
            case EMPRESA -> recorrenteRepository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(
                    contaId, statusAtivos).isPresent();
            case ENTREGADOR -> recorrenteRepository.findFirstByEntregadorIdAndStatusInOrderByIdDesc(
                    contaId, statusAtivos).isPresent();
        };
        boolean tentativaIncerta = switch (tipoConta) {
            case EMPRESA -> recorrenteRepository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(
                    contaId, estadosIncertos).isPresent();
            case ENTREGADOR -> recorrenteRepository.findFirstByEntregadorIdAndEstadoCriacaoInOrderByIdDesc(
                    contaId, estadosIncertos).isPresent();
        };
        if (possuiRecorrente || tentativaIncerta) {
            throw new IllegalStateException(
                    "Existe uma assinatura recorrente ou tentativa não resolvida. Concilie ou cancele a contratação anterior antes de gerar um Pix.");
        }

        List<PagamentoAssinatura> pagamentos = switch (tipoConta) {
            case EMPRESA -> pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(contaId);
            case ENTREGADOR -> pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(contaId);
        };

        for (PagamentoAssinatura pagamento : pagamentos) {
            if (!pertenceAoTitular(pagamento, tipoConta, contaId)) {
                throw new IllegalStateException("Pagamento com titularidade inconsistente.");
            }
            if (pagamentoAtual != null && pagamentoAtual.getId() != null
                    && pagamentoAtual.getId().equals(pagamento.getId())) {
                continue;
            }
            boolean pendente = pagamento.getStatus() == PagamentoAssinatura.Status.PENDENTE;
            boolean aprovadoNaoAtivado = pagamento.getStatus() == PagamentoAssinatura.Status.APROVADO
                    && pagamento.getDataVencimento() == null;
            if (pendente || aprovadoNaoAtivado) {
                throw new IllegalStateException(
                        "Existe uma cobrança não resolvida. Consulte ou concilie o pagamento anterior antes de gerar outro Pix.");
            }
        }
    }

    private void validarContratacaoPix(Assinatura.TipoConta tipoConta, Long contaId, Assinatura.Plano plano) {
        Assinatura atual = entityManager.createQuery(
                        "select a from Assinatura a where a.tipoConta = :tipo "
                                + "and a.contaId = :contaId and a.status = :status order by a.id desc",
                        Assinatura.class)
                .setParameter("tipo", tipoConta)
                .setParameter("contaId", contaId)
                .setParameter("status", Assinatura.Status.ATIVA)
                .setMaxResults(1)
                .getResultStream()
                .findFirst()
                .orElse(null);

        if (atual == null || atual.getDataVencimento() != null
                && !atual.getDataVencimento().isAfter(LocalDateTime.now(FUSO))) {
            return;
        }

        if (atual.getPlanoAgendado() != null) {
            throw new IllegalStateException(
                    "Existe uma troca de plano agendada. Aguarde o vencimento para contratar um novo plano.");
        }

        if (atual.isRenovacaoAutomatica()) {
            throw new IllegalStateException(
                    "Existe uma assinatura com renovação automática ativa. Cancele a renovação antes de pagar por Pix.");
        }

        if (!atual.isTesteGratuito()
                && atual.getPlano() != Assinatura.Plano.GRATUITO
                && atual.getPlano() != plano) {
            throw new IllegalStateException(
                    "A troca para outro plano só pode ser contratada após o vencimento atual.");
        }
    }

    private void validarTrocaProgramada(AssinaturaRecorrente recorrente) {
        Assinatura atual = entityManager.createQuery(
                        "select a from Assinatura a where a.tipoConta = :tipo "
                                + "and a.contaId = :contaId and a.status = :status order by a.id desc",
                        Assinatura.class)
                .setParameter("tipo", recorrente.getTipoConta())
                .setParameter("contaId", recorrente.getContaId())
                .setParameter("status", Assinatura.Status.ATIVA)
                .setMaxResults(1)
                .getResultStream()
                .findFirst()
                .orElse(null);

        if (atual == null || atual.getPlanoAgendado() == null) {
            return;
        }

        if (atual.getDataTrocaAgendada() == null || atual.getDataVencimento() == null
                || !atual.getDataTrocaAgendada().equals(atual.getDataVencimento())) {
            throw new IllegalStateException("A troca programada possui uma data inconsistente.");
        }

        if (atual.getMercadoPagoAssinaturaId() == null
                || !atual.getMercadoPagoAssinaturaId().equals(recorrente.getMercadoPagoAssinaturaId())) {
            throw new IllegalStateException("A troca programada pertence a outra assinatura recorrente.");
        }

        if (LocalDateTime.now(FUSO).isBefore(atual.getDataTrocaAgendada())) {
            throw new IllegalStateException(
                    "Existe uma troca programada. A mensalidade não pode ser ativada antes do vencimento atual."
            );
        }

        if (recorrente.getPlano() != atual.getPlanoAgendado()
                || recorrente.getValor() == null
                || recorrente.getValor().compareTo(AssinaturaService.valorDoPlano(recorrente.getTipoConta(), atual.getPlanoAgendado())) != 0) {
            throw new IllegalStateException(
                    "A cobrança recorrente ainda não corresponde ao plano agendado. "
                            + "É necessário conciliar o novo valor antes de ativar a mensalidade."
            );
        }
    }

    private Empresa obterEmpresaComBloqueio(Long empresaId) {
        if (empresaId == null || empresaId <= 0) {
            throw new IllegalArgumentException("Empresa inválida.");
        }
        Empresa empresa = entityManager.find(Empresa.class, empresaId, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        if (empresa == null) {
            throw new IllegalArgumentException("Empresa não encontrada.");
        }
        return empresa;
    }

    private PagamentoAssinatura registrarPagamento(
            Assinatura.TipoConta tipoConta, Long contaId, Assinatura.Plano plano,
            BigDecimal valor, String chaveIdempotencia
    ) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        atribuirTitular(pagamento, tipoConta, contaId);
        pagamento.setPlano(plano);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setValor(valor);
        pagamento.setChaveIdempotencia(chaveIdempotencia);
        return pagamentoRepository.saveAndFlush(pagamento);
    }

    private Empresa obterEmpresa(Long empresaId) {
        if (empresaId == null || empresaId <= 0) {
            throw new IllegalArgumentException("Empresa inválida.");
        }
        Empresa empresa = entityManager.find(Empresa.class, empresaId);
        if (empresa == null || empresa.getEmail() == null || empresa.getEmail().isBlank()) {
            throw new IllegalArgumentException("Empresa não encontrada ou sem e-mail cadastrado.");
        }
        return empresa;
    }

    private void validarConta(Assinatura.TipoConta tipoConta, Long contaId) {
        if (tipoConta == null || contaId == null || contaId <= 0) {
            throw new IllegalArgumentException("Conta inválida.");
        }
    }

    private String obterEmailConta(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            return obterEmpresa(contaId).getEmail();
        }
        Usuario entregador = entityManager.find(Usuario.class, contaId);
        if (entregador == null || entregador.getEmail() == null || entregador.getEmail().isBlank()) {
            throw new IllegalArgumentException("Entregador não encontrado ou sem e-mail cadastrado.");
        }
        return entregador.getEmail();
    }

    private Long bloquearConta(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            return obterEmpresaComBloqueio(contaId).getId();
        }
        Usuario entregador = entityManager.find(Usuario.class, contaId,
                jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        if (entregador == null) {
            throw new IllegalArgumentException("Entregador não encontrado.");
        }
        return entregador.getId();
    }

    private void atribuirTitular(PagamentoAssinatura pagamento, Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        switch (tipoConta) {
            case EMPRESA -> pagamento.setEmpresaId(contaId);
            case ENTREGADOR -> pagamento.setEntregadorId(contaId);
        }
    }

    private boolean pertenceAoTitular(PagamentoAssinatura pagamento, Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        return switch (tipoConta) {
            case EMPRESA -> contaId.equals(pagamento.getEmpresaId()) && pagamento.getEntregadorId() == null;
            case ENTREGADOR -> contaId.equals(pagamento.getEntregadorId()) && pagamento.getEmpresaId() == null;
        };
    }

    private void validarChave(String chave) {
        if (chave == null || chave.isBlank() || chave.length() > 100) {
            throw new IllegalArgumentException("Chave de idempotência inválida.");
        }
        try {
            UUID.fromString(chave);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("A chave de idempotência deve ser um UUID válido.");
        }
    }

    private void atualizarStatusEAtivar(PagamentoAssinatura pagamento, JsonNode resposta) {
        registrarStatusPix(pagamento, resposta);
        ativarPixAprovado(pagamento);
    }

    private void registrarStatusPix(PagamentoAssinatura pagamento, JsonNode resposta) {
        String id = texto(resposta, "id");
        if (id == null || !id.equals(pagamento.getMercadoPagoPagamentoId())) {
            throw new IllegalStateException("Identificador de pagamento inconsistente.");
        }

        String referencia = texto(resposta, "external_reference");
        if (!(("entregueja-pagamento-" + pagamento.getId()).equals(referencia))) {
            throw new IllegalStateException("Referência externa do pagamento inconsistente.");
        }

        JsonNode valorExterno = resposta.path("transaction_amount");
        if (!valorExterno.isNumber() || valorExterno.decimalValue().compareTo(pagamento.getValor()) != 0) {
            throw new IllegalStateException("Valor do pagamento inconsistente.");
        }

        String moeda = texto(resposta, "currency_id");
        if (!"BRL".equals(moeda)) {
            throw new IllegalStateException("Moeda do pagamento inconsistente.");
        }

        String forma = texto(resposta, "payment_method_id");
        if (!"pix".equalsIgnoreCase(forma)) {
            throw new IllegalStateException("A cobrança não corresponde a um pagamento Pix.");
        }

        String statusExterno = texto(resposta, "status");
        if (statusExterno == null) {
            throw new IllegalStateException("Status do pagamento não informado.");
        }

        PagamentoAssinatura.Status status = switch (statusExterno) {
            case "approved" -> PagamentoAssinatura.Status.APROVADO;
            case "rejected" -> PagamentoAssinatura.Status.RECUSADO;
            case "cancelled" -> PagamentoAssinatura.Status.CANCELADO;
            case "refunded", "charged_back" -> PagamentoAssinatura.Status.REEMBOLSADO;
            default -> PagamentoAssinatura.Status.PENDENTE;
        };

        validarTransicaoStatus(pagamento, status);
        pagamento.setStatus(status);
        if (status == PagamentoAssinatura.Status.APROVADO && pagamento.getDataAprovacao() == null) {
            pagamento.setDataAprovacao(LocalDateTime.now(FUSO));
        }
        pagamentoRepository.saveAndFlush(pagamento);
    }

    private void ativarPixAprovado(PagamentoAssinatura pagamento) {
        if (pagamento.getStatus() == PagamentoAssinatura.Status.APROVADO && pagamento.getDataVencimento() == null) {
            Assinatura.TipoConta tipoConta = pagamento.getTipoConta();
            Long contaId = pagamento.getContaId();
            if (tipoConta == Assinatura.TipoConta.EMPRESA) {
                assinaturaService.ativarPlanoPagoPorPix(contaId, pagamento.getId());
            } else {
                assinaturaService.ativarPlanoPagoPorPix(tipoConta, contaId, pagamento.getId());
            }
        }
    }

    private void validarTransicaoStatus(PagamentoAssinatura pagamento, PagamentoAssinatura.Status novoStatus) {
        PagamentoAssinatura.Status atual = pagamento.getStatus();
        if (atual == PagamentoAssinatura.Status.REEMBOLSADO
                && novoStatus != PagamentoAssinatura.Status.REEMBOLSADO) {
            throw new IllegalStateException("Pagamento estornado não pode retornar a outro status.");
        }
        if (atual == PagamentoAssinatura.Status.APROVADO
                && novoStatus != PagamentoAssinatura.Status.APROVADO
                && novoStatus != PagamentoAssinatura.Status.REEMBOLSADO) {
            throw new IllegalStateException("Pagamento aprovado não pode retornar a um status não final.");
        }
        if ((atual == PagamentoAssinatura.Status.CANCELADO || atual == PagamentoAssinatura.Status.RECUSADO)
                && novoStatus == PagamentoAssinatura.Status.PENDENTE) {
            throw new IllegalStateException("Pagamento finalizado não pode retornar a pendente.");
        }
    }

    private Map<String, Object> montarResposta(PagamentoAssinatura pagamento, JsonNode resposta) {
        Map<String, Object> dados = new LinkedHashMap<>();
        dados.put("pagamentoId", pagamento.getId());
        dados.put("plano", pagamento.getPlano().name());
        dados.put("valor", pagamento.getValor());
        dados.put("status", pagamento.getStatus().name());
        dados.put("mercadoPagoPagamentoId", pagamento.getMercadoPagoPagamentoId());
        dados.put("planoAtivado", pagamento.getDataVencimento() != null);
        dados.put("vencimentoPlano", pagamento.getDataVencimento());
        dados.put("tipoConta", pagamento.getTipoConta().name());
        dados.put("dataCriacao", pagamento.getDataCriacao());
        boolean consultaRealizada = resposta != null && !resposta.isMissingNode() && !resposta.isNull();
        boolean possuiIdentificador = pagamento.getMercadoPagoPagamentoId() != null
                && !pagamento.getMercadoPagoPagamentoId().isBlank();
        dados.put("consultaMercadoPagoRealizada", consultaRealizada);
        dados.put("buscaReferenciaRealizada", false);
        dados.put("situacaoRecuperacao", consultaRealizada ? "CONSULTADA"
                : possuiIdentificador ? "AGUARDANDO_CONSULTA" : "AGUARDANDO_IDENTIFICACAO");
        dados.put("requerConciliacao", pixNaoResolvido(pagamento));
        JsonNode transacao = consultaRealizada && pagamento.getStatus() == PagamentoAssinatura.Status.PENDENTE
                ? resposta.path("point_of_interaction").path("transaction_data")
                : MissingNode.getInstance();
        dados.put("pixCopiaECola", texto(transacao, "qr_code"));
        dados.put("pixQrCodeBase64", texto(transacao, "qr_code_base64"));
        dados.put("pixLink", texto(transacao, "ticket_url"));
        return dados;
    }

    private String texto(JsonNode objeto, String campo) {
        if (objeto == null || objeto.isNull() || objeto.isMissingNode()) return null;
        JsonNode valor = objeto.path(campo);
        if (valor.isMissingNode() || valor.isNull() || valor.isContainerNode()) return null;
        String texto = valor.asText();
        return texto.isBlank() ? null : texto;
    }
}
