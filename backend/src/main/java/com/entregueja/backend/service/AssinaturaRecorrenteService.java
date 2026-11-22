package com.entregueja.backend.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import java.util.UUID;

@Service
public class AssinaturaRecorrenteService {

    private static final Logger log = LoggerFactory.getLogger(AssinaturaRecorrenteService.class);
    private static final ZoneId FUSO = ZoneId.of("America/Sao_Paulo");
    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

    private final AssinaturaRecorrenteRepository repository;
    private final MercadoPagoService mercadoPagoService;
    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final PagamentoAssinaturaService pagamentoService;
    private final EntityManager entityManager;
    private final String urlRetorno;
    private final TransactionTemplate transactionTemplate;

    @Autowired
    public AssinaturaRecorrenteService(
            AssinaturaRecorrenteRepository repository,
            MercadoPagoService mercadoPagoService,
            PagamentoAssinaturaRepository pagamentoRepository,
            PagamentoAssinaturaService pagamentoService,
            EntityManager entityManager,
            @Value("${mercadopago.subscription-return-url:}") String urlRetorno,
            PlatformTransactionManager transactionManager
    ) {
        this.repository = repository;
        this.mercadoPagoService = mercadoPagoService;
        this.pagamentoRepository = pagamentoRepository;
        this.pagamentoService = pagamentoService;
        this.entityManager = entityManager;
        this.urlRetorno = urlRetorno == null ? "" : urlRetorno.trim();
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    AssinaturaRecorrenteService(
            AssinaturaRecorrenteRepository repository,
            MercadoPagoService mercadoPagoService,
            PagamentoAssinaturaRepository pagamentoRepository,
            PagamentoAssinaturaService pagamentoService,
            EntityManager entityManager,
            String urlRetorno
    ) {
        this.repository = repository;
        this.mercadoPagoService = mercadoPagoService;
        this.pagamentoRepository = pagamentoRepository;
        this.pagamentoService = pagamentoService;
        this.entityManager = entityManager;
        this.urlRetorno = urlRetorno == null ? "" : urlRetorno.trim();
        this.transactionTemplate = null;
    }

    private <T> T emTransacao(java.util.function.Supplier<T> operacao) {
        if (transactionTemplate == null) return operacao.get();
        return transactionTemplate.execute(status -> operacao.get());
    }

    public Map<String, Object> criar(Long empresaId, Assinatura.Plano plano, String chaveIdempotencia, String emailPagador) {
        if (emailPagador == null || emailPagador.trim().length() > 254
                || !EMAIL_PATTERN.matcher(emailPagador.trim()).matches()) {
            throw new IllegalArgumentException("Informe um e-mail válido para o responsável pelo pagamento.");
        }
        String emailNormalizado = emailPagador.trim();
        BigDecimal valor = valorDoPlano(plano);
        validarChave(chaveIdempotencia);

        boolean[] criadoAgora = {false};
        AssinaturaRecorrente registro = emTransacao(() -> {
            obterEmpresaComBloqueio(empresaId);
            AssinaturaRecorrente existente = repository.findByChaveIdempotencia(chaveIdempotencia).orElse(null);
            if (existente != null) {
                if (!empresaId.equals(existente.getEmpresaId()) || existente.getPlano() != plano
                        || existente.getValor().compareTo(valor) != 0
                        || existente.getEmailPagador() == null
                        || !existente.getEmailPagador().equalsIgnoreCase(emailNormalizado)) {
                    throw new IllegalArgumentException("Chave de idempotência vinculada a outra solicitação.");
                }
                return existente;
            }
            boolean possuiAssinatura = repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(
                    empresaId,
                    List.of(AssinaturaRecorrente.Status.PENDENTE,
                            AssinaturaRecorrente.Status.AUTORIZADA,
                            AssinaturaRecorrente.Status.PAUSADA)
            ).isPresent();
            boolean tentativaIncerta = repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(
                    empresaId,
                    List.of(AssinaturaRecorrente.EstadoCriacao.PREPARADA,
                            AssinaturaRecorrente.EstadoCriacao.ENVIANDO,
                            AssinaturaRecorrente.EstadoCriacao.INCERTA)
            ).isPresent();
            if (possuiAssinatura || tentativaIncerta) {
                throw new IllegalStateException("A empresa já possui uma assinatura recorrente ou tentativa não resolvida.");
            }
            if (urlRetorno.isBlank()) {
                throw new IllegalStateException("URL de retorno das assinaturas não configurada.");
            }
            AssinaturaRecorrente novo = new AssinaturaRecorrente();
            novo.setEmpresaId(empresaId);
            novo.setPlano(plano);
            novo.setValor(valor);
            novo.setEmailPagador(emailNormalizado);
            novo.setStatus(AssinaturaRecorrente.Status.PENDENTE);
            novo.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.PREPARADA);
            novo.setChaveIdempotencia(chaveIdempotencia);
            criadoAgora[0] = true;
            return repository.saveAndFlush(novo);
        });

        if (!criadoAgora[0] || registro.getEstadoCriacao() != AssinaturaRecorrente.EstadoCriacao.PREPARADA
                || registro.getMercadoPagoAssinaturaId() != null) {
            return resposta(registro);
        }

        Long idRegistro = registro.getId();
        boolean deveEnviar = emTransacao(() -> {
            AssinaturaRecorrente atual = transactionTemplate == null
                    ? registro
                    : repository.buscarPorIdComBloqueio(idRegistro).orElseThrow(
                    () -> new IllegalStateException("Tentativa de assinatura não encontrada."));
            if (atual.getEstadoCriacao() != AssinaturaRecorrente.EstadoCriacao.PREPARADA) return false;
            atual.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.ENVIANDO);
            repository.save(atual);
            return true;
        });
        if (!deveEnviar) {
            return resposta(emTransacao(() -> repository.findById(idRegistro).orElseThrow()));
        }

        JsonNode externo;
        try {
            externo = mercadoPagoService.criarAssinaturaRecorrente(
                    "Entregue Já - " + plano.name(), emailNormalizado,
                    "entregueja-recorrente-" + idRegistro, valor, urlRetorno);
            validarIdentidade(externo, registro);
            String idExterno = texto(externo, "id");
            if (idExterno == null || !idExterno.matches("[A-Za-z0-9_-]{1,100}")) {
                throw new IllegalStateException("Identificador de assinatura inválido no Mercado Pago.");
            }
            return emTransacao(() -> {
                AssinaturaRecorrente atual = transactionTemplate == null
                        ? registro
                        : repository.buscarPorIdComBloqueio(idRegistro).orElseThrow(
                        () -> new IllegalStateException("Tentativa de assinatura não encontrada."));
                validarIdentidade(externo, atual);
                atual.setMercadoPagoAssinaturaId(idExterno);
                atual.setUrlAutorizacao(texto(externo, "init_point"));
                atualizarStatus(atual, externo);
                atual.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
                return resposta(repository.save(atual));
            });
        } catch (RuntimeException erro) {
            try {
                emTransacao(() -> {
                    AssinaturaRecorrente atual = transactionTemplate == null
                            ? registro
                            : repository.buscarPorIdComBloqueio(idRegistro).orElseThrow();
                    if (atual.getEstadoCriacao() != AssinaturaRecorrente.EstadoCriacao.CONFIRMADA) {
                        atual.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
                        repository.save(atual);
                    }
                    return null;
                });
            } catch (RuntimeException falhaRegistro) {
                erro.addSuppressed(falhaRegistro);
            }
            throw erro;
        }
    }

    @Transactional
    public Map<String, Object> sincronizarNotificacao(String assinaturaExternaId) {
        if (assinaturaExternaId == null || !assinaturaExternaId.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new IllegalArgumentException("Identificador externo da assinatura inválido.");
        }

        AssinaturaRecorrente registro = repository.findByMercadoPagoAssinaturaId(assinaturaExternaId)
                .orElseThrow(() -> new IllegalStateException("Assinatura recorrente não encontrada."));

        obterEmpresaComBloqueio(registro.getEmpresaId());
        JsonNode externo = mercadoPagoService.consultarAssinaturaRecorrente(assinaturaExternaId);
        validarIdentidade(externo, registro);
        atualizarStatus(registro, externo);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        return resposta(repository.saveAndFlush(registro));
    }

    @Transactional
    public Map<String, Object> consultar(Long empresaId, Long assinaturaId) {
        obterEmpresaComBloqueio(empresaId);
        AssinaturaRecorrente registro = obterRegistro(empresaId, assinaturaId);
        if (registro.getMercadoPagoAssinaturaId() == null) {
            return resposta(registro);
        }
        JsonNode externo = mercadoPagoService.consultarAssinaturaRecorrente(registro.getMercadoPagoAssinaturaId());
        validarIdentidade(externo, registro);
        atualizarStatus(registro, externo);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        return resposta(repository.save(registro));
    }

    @Transactional
    public Map<String, Object> cancelar(Long empresaId, Long assinaturaId) {
        obterEmpresaComBloqueio(empresaId);
        AssinaturaRecorrente registro = obterRegistro(empresaId, assinaturaId);
        if (registro.getStatus() == AssinaturaRecorrente.Status.CANCELADA
                || registro.getStatus() == AssinaturaRecorrente.Status.ENCERRADA) {
            return resposta(registro);
        }
        if (registro.getMercadoPagoAssinaturaId() == null) {
            throw new IllegalStateException("A assinatura ainda não possui identificador externo. Verifique antes de cancelar.");
        }
        JsonNode externo = mercadoPagoService.cancelarAssinaturaRecorrente(registro.getMercadoPagoAssinaturaId());
        validarIdentidade(externo, registro);
        atualizarStatus(registro, externo);
        if (registro.getStatus() != AssinaturaRecorrente.Status.CANCELADA) {
            throw new IllegalStateException("O Mercado Pago ainda não confirmou o cancelamento.");
        }
        return resposta(repository.save(registro));
    }

    @Transactional(readOnly = true)
    public Map<String, Object> consultarTrocaProgramada(Long empresaId, Long assinaturaId) {
        validarEmpresaId(empresaId);
        if (entityManager.find(Empresa.class, empresaId) == null) {
            throw new IllegalArgumentException("Empresa não encontrada.");
        }

        AssinaturaRecorrente registro = repository.findById(assinaturaId == null ? -1L : assinaturaId)
                .orElseThrow(() -> new IllegalArgumentException("Assinatura recorrente não encontrada."));
        if (!empresaId.equals(registro.getEmpresaId())) {
            throw new IllegalArgumentException("Assinatura recorrente não encontrada.");
        }

        Assinatura atual = entityManager.createQuery(
                        "select a from Assinatura a where a.tipoConta = :tipo and a.contaId = :contaId "
                                + "and a.status = :status order by a.id desc", Assinatura.class)
                .setParameter("tipo", Assinatura.TipoConta.EMPRESA)
                .setParameter("contaId", empresaId)
                .setParameter("status", Assinatura.Status.ATIVA)
                .setMaxResults(1)
                .getResultStream()
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Não existe assinatura ativa."));

        if (atual.getPlanoAgendado() == null || atual.getDataTrocaAgendada() == null) {
            throw new IllegalStateException("Não existe troca de plano agendada.");
        }
        if (atual.isTesteGratuito() || atual.getPlano() == Assinatura.Plano.GRATUITO
                || atual.getDataVencimento() == null) {
            throw new IllegalStateException("A troca exige uma assinatura paga vigente.");
        }
        if (!atual.getDataTrocaAgendada().equals(atual.getDataVencimento())) {
            throw new IllegalStateException("A data da troca diverge do vencimento atual.");
        }
        if (registro.getStatus() != AssinaturaRecorrente.Status.AUTORIZADA
                || registro.getMercadoPagoAssinaturaId() == null
                || !registro.getMercadoPagoAssinaturaId().equals(atual.getMercadoPagoAssinaturaId())) {
            throw new IllegalStateException("A assinatura recorrente não corresponde ao plano ativo.");
        }

        JsonNode externo = mercadoPagoService.consultarAssinaturaRecorrente(registro.getMercadoPagoAssinaturaId());
        validarIdentidade(externo, registro);

        if (!"authorized".equalsIgnoreCase(texto(externo, "status"))) {
            throw new IllegalStateException("A assinatura não está autorizada no Mercado Pago.");
        }

        JsonNode autoRecorrente = externo.path("auto_recurring");
        BigDecimal valorExterno;
        try {
            valorExterno = new BigDecimal(autoRecorrente.path("transaction_amount").asText());
        } catch (RuntimeException e) {
            throw new IllegalStateException("Não foi possível validar o valor atual no Mercado Pago.");
        }
        if (valorExterno.compareTo(registro.getValor()) != 0) {
            throw new IllegalStateException("O valor da assinatura diverge do Mercado Pago.");
        }
        if (!"BRL".equals(texto(autoRecorrente, "currency_id"))) {
            throw new IllegalStateException("A moeda da assinatura no Mercado Pago não é BRL.");
        }
        if (registro.getPlano() != atual.getPlano()) {
            throw new IllegalStateException("O plano recorrente não corresponde ao plano ativo.");
        }
        if (atual.getPlanoAgendado() == atual.getPlano()) {
            throw new IllegalStateException("O plano agendado já é o plano atual.");
        }
        if (atual.getDataTrocaAgendada().isBefore(LocalDateTime.now(FUSO))) {
            throw new IllegalStateException("A data agendada já passou. É necessária conciliação manual.");
        }

        Map<String, Object> dados = new LinkedHashMap<>();
        dados.put("empresaId", empresaId);
        dados.put("assinaturaId", registro.getId());
        dados.put("planoAtual", atual.getPlano().name());
        dados.put("planoAgendado", atual.getPlanoAgendado().name());
        dados.put("vencimentoAtual", atual.getDataVencimento());
        dados.put("dataTrocaAgendada", atual.getDataTrocaAgendada());
        dados.put("valorAtual", valorExterno);
        dados.put("valorNovo", valorDoPlano(atual.getPlanoAgendado()));
        dados.put("proximaCobrancaMercadoPago", texto(externo, "next_payment_date"));
        dados.put("dataConsulta", LocalDateTime.now(FUSO));
        dados.put("atualizacaoAutomaticaHabilitada", false);
        dados.put("motivoBloqueio", "A data efetiva da próxima cobrança deve ser validada antes da atualização do preço.");
        return dados;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> simularSincronizacaoTroca(Long empresaId, Long assinaturaId) {
        Map<String, Object> consulta = consultarTrocaProgramada(empresaId, assinaturaId);
        String proximaCobranca = (String) consulta.get("proximaCobrancaMercadoPago");

        Map<String, Object> simulacao = new LinkedHashMap<>(consulta);
        simulacao.put("operacao", "SIMULACAO");
        simulacao.put("alteracaoMercadoPagoExecutada", false);
        simulacao.put("alteracaoBancoExecutada", false);
        simulacao.put("novoPlanoAtivado", false);
        simulacao.put("proximoValorEsperado", consulta.get("valorNovo"));

        if (proximaCobranca == null) {
            simulacao.put("situacao", "BLOQUEADA");
            simulacao.put("pendencia", "O Mercado Pago não informou a data da próxima cobrança.");
            return simulacao;
        }

        try {
            OffsetDateTime dataCobranca = OffsetDateTime.parse(proximaCobranca);
            simulacao.put("proximaCobrancaInterpretada", dataCobranca);
            simulacao.put("situacao", "AGUARDANDO_TESTE_INTEGRACAO");
            simulacao.put("pendencia",
                    "Validar em ambiente de testes quando a alteração do valor passa a valer "
                            + "e se a próxima cobrança preserva o ciclo vigente.");
        } catch (DateTimeParseException e) {
            simulacao.put("situacao", "BLOQUEADA");
            simulacao.put("pendencia", "Formato da próxima data de cobrança não reconhecido.");
        }
        return simulacao;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listar(Long empresaId) {
        validarEmpresaId(empresaId);
        if (entityManager.find(Empresa.class, empresaId) == null) {
            throw new IllegalArgumentException("Empresa não encontrada.");
        }
        return repository.findByEmpresaIdOrderByIdDesc(empresaId).stream().map(this::resposta).toList();
    }

    public Map<String, Object> conciliarPagamentos(Long empresaId) {
        validarEmpresaId(empresaId);
        if (entityManager.find(Empresa.class, empresaId) == null) {
            throw new IllegalArgumentException("Empresa não encontrada.");
        }

        List<PagamentoAssinatura> pagamentos = pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(empresaId);
        int consultados = 0;
        int aprovados = 0;
        int falhas = 0;
        int ignorados = 0;

        for (PagamentoAssinatura pagamento : pagamentos) {
            String idExterno = pagamento.getMercadoPagoPagamentoId();
            if (idExterno == null || idExterno.isBlank()
                    || pagamento.getStatus() == PagamentoAssinatura.Status.REEMBOLSADO) {
                ignorados++;
                continue;
            }

            boolean pendente = pagamento.getStatus() == PagamentoAssinatura.Status.PENDENTE;
            boolean aprovadoNaoAtivado = pagamento.getStatus() == PagamentoAssinatura.Status.APROVADO
                    && pagamento.getDataVencimento() == null;
            if (!pendente && !aprovadoNaoAtivado) {
                ignorados++;
                continue;
            }

            try {
                Map<String, Object> resultado;
                if (pagamento.getFormaPagamento() == PagamentoAssinatura.FormaPagamento.PIX) {
                    resultado = pagamentoService.consultarCobrancaPix(empresaId, pagamento.getId());
                } else if (pagamento.getFormaPagamento() == PagamentoAssinatura.FormaPagamento.CARTAO) {
                    resultado = pagamentoService.processarPagamentoRecorrente(idExterno);
                } else {
                    ignorados++;
                    continue;
                }
                consultados++;
                if ("APROVADO".equals(resultado.get("status"))
                        && Boolean.TRUE.equals(resultado.get("planoAtivado"))) {
                    aprovados++;
                }
            } catch (RuntimeException e) {
                falhas++;
                log.warn("Falha ao conciliar pagamento da empresa {}: {}", empresaId, e.getClass().getSimpleName());
            }
        }

        Map<String, Object> recuperacao = null;
        String erroRecuperacao = null;
        try {
            recuperacao = pagamentoService.recuperarMensalidadesRecorrentes(empresaId);
        } catch (RuntimeException e) {
            falhas++;
            erroRecuperacao = "Não foi possível concluir a recuperação de mensalidades recorrentes.";
            log.warn("Falha ao recuperar mensalidades da empresa {}: {}", empresaId, e.getClass().getSimpleName());
        }

        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("empresaId", empresaId);
        resultado.put("consultados", consultados);
        resultado.put("aprovadosAtivados", aprovados);
        resultado.put("falhas", falhas);
        resultado.put("ignorados", ignorados);
        resultado.put("totalRegistros", pagamentos.size());
        resultado.put("recuperacaoMensalidades", recuperacao);
        resultado.put("erroRecuperacao", erroRecuperacao);
        return resultado;
    }

    private AssinaturaRecorrente obterRegistro(Long empresaId, Long assinaturaId) {
        if (assinaturaId == null || assinaturaId <= 0) {
            throw new IllegalArgumentException("Assinatura inválida.");
        }
        AssinaturaRecorrente registro = repository.buscarPorIdComBloqueio(assinaturaId)
                .orElseThrow(() -> new IllegalArgumentException("Assinatura não encontrada."));
        if (!empresaId.equals(registro.getEmpresaId())) {
            throw new IllegalArgumentException("Assinatura não encontrada.");
        }
        return registro;
    }

    private Empresa obterEmpresaComBloqueio(Long empresaId) {
        validarEmpresaId(empresaId);
        Empresa empresa = entityManager.find(Empresa.class, empresaId, LockModeType.PESSIMISTIC_WRITE);
        if (empresa == null || empresa.getEmail() == null || empresa.getEmail().isBlank()) {
            throw new IllegalArgumentException("Empresa não encontrada ou sem e-mail cadastrado.");
        }
        return empresa;
    }

    private void validarEmpresaId(Long empresaId) {
        if (empresaId == null || empresaId <= 0) {
            throw new IllegalArgumentException("Empresa inválida.");
        }
    }

    private void validarChave(String chave) {
        if (chave == null || chave.length() > 100) {
            throw new IllegalArgumentException("Chave de idempotência inválida.");
        }
        try {
            UUID.fromString(chave);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("A chave de idempotência deve ser um UUID válido.");
        }
    }

    private BigDecimal valorDoPlano(Assinatura.Plano plano) {
        if (plano == Assinatura.Plano.ESSENCIAL) return new BigDecimal("39.90");
        if (plano == Assinatura.Plano.PROFISSIONAL) return new BigDecimal("79.90");
        throw new IllegalArgumentException("Selecione um plano pago válido.");
    }

    private void validarIdentidade(JsonNode externo, AssinaturaRecorrente registro) {
        String referencia = texto(externo, "external_reference");
        if (!("entregueja-recorrente-" + registro.getId()).equals(referencia)) {
            throw new IllegalStateException("Referência externa da assinatura inconsistente.");
        }
        String id = texto(externo, "id");
        if (registro.getMercadoPagoAssinaturaId() != null
                && !registro.getMercadoPagoAssinaturaId().equals(id)) {
            throw new IllegalStateException("Identificador externo da assinatura inconsistente.");
        }
    }

    private void atualizarStatus(AssinaturaRecorrente registro, JsonNode externo) {
        String status = texto(externo, "status");
        if (status == null) throw new IllegalStateException("Status externo não informado.");
        switch (status.toLowerCase(java.util.Locale.ROOT)) {
            case "pending" -> registro.setStatus(AssinaturaRecorrente.Status.PENDENTE);
            case "authorized" -> registro.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
            case "paused" -> registro.setStatus(AssinaturaRecorrente.Status.PAUSADA);
            case "cancelled" -> {
                registro.setStatus(AssinaturaRecorrente.Status.CANCELADA);
                if (registro.getDataCancelamento() == null) registro.setDataCancelamento(LocalDateTime.now());
            }
            case "finished" -> registro.setStatus(AssinaturaRecorrente.Status.ENCERRADA);
            default -> throw new IllegalStateException("Status externo da assinatura desconhecido.");
        }
    }

    private Map<String, Object> resposta(AssinaturaRecorrente registro) {
        Map<String, Object> dados = new LinkedHashMap<>();
        dados.put("assinaturaId", registro.getId());
        dados.put("plano", registro.getPlano().name());
        dados.put("valorMensal", registro.getValor());
        dados.put("status", registro.getStatus().name());
        dados.put("estadoCriacao", registro.getEstadoCriacao() == null ? null : registro.getEstadoCriacao().name());
        dados.put("mercadoPagoAssinaturaId", registro.getMercadoPagoAssinaturaId());
        dados.put("urlAutorizacao", registro.getUrlAutorizacao());
        dados.put("dataCriacao", registro.getDataCriacao());
        dados.put("dataCancelamento", registro.getDataCancelamento());
        dados.put("planoAtivado", false);
        return dados;
    }

    private String texto(JsonNode objeto, String campo) {
        JsonNode valor = objeto.path(campo);
        if (valor.isMissingNode() || valor.isNull() || valor.isContainerNode()) return null;
        String texto = valor.asText();
        return texto.isBlank() ? null : texto;
    }
}