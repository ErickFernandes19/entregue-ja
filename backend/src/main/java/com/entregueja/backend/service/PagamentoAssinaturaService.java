package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.LinkedHashMap;
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

    public PagamentoAssinaturaService(
            PagamentoAssinaturaRepository pagamentoRepository,
            AssinaturaRecorrenteRepository recorrenteRepository,
            MercadoPagoService mercadoPagoService,
            AssinaturaService assinaturaService,
            EntityManager entityManager
    ) {
        this.pagamentoRepository = pagamentoRepository;
        this.recorrenteRepository = recorrenteRepository;
        this.mercadoPagoService = mercadoPagoService;
        this.assinaturaService = assinaturaService;
        this.entityManager = entityManager;
    }

    @Transactional(noRollbackFor = MercadoPagoService.MercadoPagoException.class)
    public Map<String, Object> criarCobrancaPix(Long empresaId, Assinatura.Plano plano, String chaveIdempotencia) {
        Empresa empresa = obterEmpresa(empresaId);
        BigDecimal valor = valorDoPlano(plano);
        validarChave(chaveIdempotencia);

        obterEmpresaComBloqueio(empresaId);

        PagamentoAssinatura pagamento = pagamentoRepository.findByChaveIdempotencia(chaveIdempotencia)
                .orElseGet(() -> registrarPagamento(empresaId, plano, valor, chaveIdempotencia));

        if (!empresaId.equals(pagamento.getEmpresaId())
                || pagamento.getPlano() != plano
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX
                || pagamento.getValor().compareTo(valor) != 0) {
            throw new IllegalArgumentException("A chave de idempotência já pertence a outra cobrança.");
        }

        if (pagamento.getMercadoPagoPagamentoId() != null) {
            JsonNode consulta = mercadoPagoService.consultarPagamento(pagamento.getMercadoPagoPagamentoId());
            atualizarStatusEAtivar(pagamento, consulta);
            return montarResposta(pagamento, consulta);
        }

        if (pagamento.getStatus() != PagamentoAssinatura.Status.PENDENTE) {
            throw new IllegalStateException("Esta cobrança não está mais pendente.");
        }

        JsonNode resposta = mercadoPagoService.criarPagamentoPix(
                valor,
                "Assinatura Entregue Já - " + plano.name(),
                empresa.getEmail(),
                "entregueja-pagamento-" + pagamento.getId(),
                pagamento.getChaveIdempotencia()
        );

        String idExterno = texto(resposta, "id");
        if (idExterno == null || !idExterno.matches("[0-9]+")) {
            throw new IllegalStateException("O Mercado Pago não retornou um identificador válido.");
        }

        pagamento.setMercadoPagoPagamentoId(idExterno);
        atualizarStatusEAtivar(pagamento, resposta);
        return montarResposta(pagamento, resposta);
    }

    @Transactional
    public Map<String, Object> consultarCobrancaPix(Long empresaId, Long pagamentoId) {
        obterEmpresa(empresaId);
        obterEmpresaComBloqueio(empresaId);
        PagamentoAssinatura pagamento = pagamentoRepository.buscarPorIdComBloqueio(pagamentoId)
                .orElseThrow(() -> new IllegalArgumentException("Pagamento não encontrado."));

        if (!empresaId.equals(pagamento.getEmpresaId())
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX) {
            throw new IllegalArgumentException("Pagamento não encontrado.");
        }

        if (pagamento.getMercadoPagoPagamentoId() == null) {
            throw new IllegalStateException("A cobrança ainda não possui identificador externo.");
        }

        JsonNode resposta = mercadoPagoService.consultarPagamento(pagamento.getMercadoPagoPagamentoId());
        atualizarStatusEAtivar(pagamento, resposta);
        return montarResposta(pagamento, resposta);
    }


    @Transactional
    public Map<String, Object> processarPagamentoRecorrente(String mercadoPagoPagamentoId) {
        if (mercadoPagoPagamentoId == null || !mercadoPagoPagamentoId.matches("[0-9]+")) {
            throw new IllegalArgumentException("Identificador do pagamento inválido.");
        }

        JsonNode externo = mercadoPagoService.consultarPagamento(mercadoPagoPagamentoId);
        if (!mercadoPagoPagamentoId.equals(texto(externo, "id"))) {
            throw new IllegalStateException("Identificador externo do pagamento inconsistente.");
        }

        String assinaturaExterna = texto(externo, "preapproval_id");
        if (assinaturaExterna == null) {
            assinaturaExterna = texto(externo.path("metadata"), "preapproval_id");
        }
        if (assinaturaExterna == null) {
            throw new IllegalStateException("Não foi possível comprovar a assinatura recorrente vinculada à cobrança.");
        }

        final String idAssinaturaExterna = assinaturaExterna;
        AssinaturaRecorrente recorrente = recorrenteRepository
                .findByMercadoPagoAssinaturaId(assinaturaExterna)
                .orElseThrow(() -> new IllegalStateException("Assinatura recorrente não encontrada."));

        Empresa empresa = obterEmpresaComBloqueio(recorrente.getEmpresaId());
        if (empresa.getId() == null) {
            throw new IllegalStateException("Empresa inválida.");
        }

        validarTrocaProgramada(recorrente);

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
        if (!valorExterno.isNumber() || valorExterno.decimalValue().compareTo(recorrente.getValor()) != 0
                || !"BRL".equals(texto(externo, "currency_id"))
                || !"credit_card".equals(texto(externo, "payment_type_id"))) {
            throw new IllegalStateException("Dados da cobrança recorrente inconsistentes.");
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
                    novo.setEmpresaId(recorrente.getEmpresaId());
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

        if (!recorrente.getEmpresaId().equals(pagamento.getEmpresaId())
                || pagamento.getPlano() != recorrente.getPlano()
                || pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.CARTAO
                || !assinaturaExterna.equals(pagamento.getMercadoPagoAssinaturaId())
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
            assinaturaService.ativarPlanoPagoPorCartao(recorrente.getEmpresaId(), pagamento.getId());
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
        obterEmpresaComBloqueio(empresaId);

        int assinaturasConsultadas = 0;
        int mensalidadesEncontradas = 0;
        int mensalidadesProcessadas = 0;
        int mensalidadesJaRegistradas = 0;

        for (AssinaturaRecorrente recorrente : recorrenteRepository.findByEmpresaIdOrderByIdDesc(empresaId)) {
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
            final int limite = 100;
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
                    processarPagamentoRecorrente(pagamentoExterno);
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

    private void validarTrocaProgramada(AssinaturaRecorrente recorrente) {
        Assinatura atual = entityManager.createQuery(
                        "select a from Assinatura a where a.tipoConta = :tipo "
                                + "and a.contaId = :contaId and a.status = :status order by a.id desc",
                        Assinatura.class)
                .setParameter("tipo", Assinatura.TipoConta.EMPRESA)
                .setParameter("contaId", recorrente.getEmpresaId())
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
                || recorrente.getValor().compareTo(valorDoPlano(atual.getPlanoAgendado())) != 0) {
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
            Long empresaId, Assinatura.Plano plano, BigDecimal valor, String chaveIdempotencia
    ) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(empresaId);
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

    private BigDecimal valorDoPlano(Assinatura.Plano plano) {
        if (plano == Assinatura.Plano.ESSENCIAL) return new BigDecimal("39.90");
        if (plano == Assinatura.Plano.PROFISSIONAL) return new BigDecimal("79.90");
        throw new IllegalArgumentException("Selecione um plano pago válido.");
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

        if (status == PagamentoAssinatura.Status.APROVADO && pagamento.getDataVencimento() == null) {
            assinaturaService.ativarPlanoPagoPorPix(pagamento.getEmpresaId(), pagamento.getId());
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
        JsonNode transacao = resposta.path("point_of_interaction").path("transaction_data");
        dados.put("pixCopiaECola", texto(transacao, "qr_code"));
        dados.put("pixQrCodeBase64", texto(transacao, "qr_code_base64"));
        dados.put("pixLink", texto(transacao, "ticket_url"));
        return dados;
    }

    private String texto(JsonNode objeto, String campo) {
        JsonNode valor = objeto.path(campo);
        if (valor.isMissingNode() || valor.isNull() || valor.isContainerNode()) return null;
        String texto = valor.asText();
        return texto.isBlank() ? null : texto;
    }
}
