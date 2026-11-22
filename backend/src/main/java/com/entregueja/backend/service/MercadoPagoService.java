package com.entregueja.backend.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.URI;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class MercadoPagoService {

    private final RestClient cliente;
    private final ObjectMapper objectMapper;
    private final String accessToken;
    private final String subscriptionsAccessToken;

    public MercadoPagoService(
            @Value("${mercadopago.access-token:}") String accessToken,
            @Value("${MERCADO_PAGO_SUBSCRIPTIONS_ACCESS_TOKEN:}") String subscriptionsAccessToken,
            ObjectMapper objectMapper
    ) {
        this.accessToken = accessToken == null ? "" : accessToken.trim();
        this.subscriptionsAccessToken = subscriptionsAccessToken == null ? "" : subscriptionsAccessToken.trim();
        this.objectMapper = objectMapper;
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(10));
        factory.setReadTimeout(Duration.ofSeconds(20));
        this.cliente = RestClient.builder()
                .baseUrl("https://api.mercadopago.com")
                .requestFactory(factory)
                .build();
    }

    public JsonNode criarPagamentoPix(
            BigDecimal valor,
            String descricao,
            String emailPagador,
            String referenciaExterna,
            String chaveIdempotencia
    ) {
        validarConfiguracao();
        validarValor(valor);
        validarTexto(descricao, "Descrição obrigatória.");
        validarTexto(emailPagador, "E-mail do pagador obrigatório.");
        validarTexto(referenciaExterna, "Referência externa obrigatória.");
        validarTexto(chaveIdempotencia, "Chave de idempotência obrigatória.");
        if (chaveIdempotencia.length() > 100 || !chaveIdempotencia.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new IllegalArgumentException("Chave de idempotência inválida.");
        }

        Map<String, Object> corpo = new LinkedHashMap<>();
        corpo.put("transaction_amount", valor.setScale(2, RoundingMode.UNNECESSARY));
        corpo.put("description", descricao.trim());
        corpo.put("payment_method_id", "pix");
        corpo.put("payer", Map.of("email", emailPagador.trim()));
        corpo.put("external_reference", referenciaExterna.trim());

        try {
            return interpretarResposta(cliente.post()
                    .uri("/v1/payments")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                    .header("X-Idempotency-Key", chaveIdempotencia.trim())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(corpo)
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("criar pagamento Pix", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode consultarPagamento(String pagamentoId) {
        validarConfiguracao();
        if (pagamentoId == null || !pagamentoId.matches("[0-9]+")) {
            throw new IllegalArgumentException("Identificador de pagamento inválido.");
        }
        try {
            return interpretarResposta(cliente.get()
                    .uri("/v1/payments/{id}", pagamentoId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("consultar pagamento", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode consultarPagamentoRecorrente(String pagamentoId) {
        validarConfiguracaoAssinaturas();
        if (pagamentoId == null || !pagamentoId.matches("[0-9]+")) {
            throw new IllegalArgumentException("Identificador de pagamento inválido.");
        }
        try {
            return interpretarResposta(cliente.get()
                    .uri("/v1/payments/{id}", pagamentoId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("consultar pagamento recorrente", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode criarAssinaturaRecorrente(
            String motivo,
            String emailPagador,
            String referenciaExterna,
            BigDecimal valorMensal,
            String urlRetorno
    ) {
        validarConfiguracaoAssinaturas();
        validarValor(valorMensal);
        validarTexto(motivo, "Motivo da assinatura obrigatório.");
        validarTexto(emailPagador, "E-mail do pagador obrigatório.");
        validarTexto(referenciaExterna, "Referência externa obrigatória.");
        validarUrlHttps(urlRetorno);

        Map<String, Object> recorrencia = new LinkedHashMap<>();
        recorrencia.put("frequency", 1);
        recorrencia.put("frequency_type", "months");
        recorrencia.put("transaction_amount", valorMensal.setScale(2, RoundingMode.UNNECESSARY));
        recorrencia.put("currency_id", "BRL");

        Map<String, Object> corpo = new LinkedHashMap<>();
        corpo.put("reason", motivo.trim());
        corpo.put("payer_email", emailPagador.trim());
        corpo.put("external_reference", referenciaExterna.trim());
        corpo.put("auto_recurring", recorrencia);
        corpo.put("back_url", urlRetorno.trim());
        corpo.put("status", "pending");

        try {
            return interpretarResposta(cliente.post()
                    .uri("/preapproval")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(corpo)
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("criar assinatura recorrente", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode consultarAssinaturaRecorrente(String assinaturaId) {
        validarConfiguracaoAssinaturas();
        validarIdentificadorAssinatura(assinaturaId);
        try {
            return interpretarResposta(cliente.get()
                    .uri("/preapproval/{id}", assinaturaId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("consultar assinatura recorrente", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode consultarPagamentoAutorizado(String pagamentoAutorizadoId) {
        validarConfiguracaoAssinaturas();
        if (pagamentoAutorizadoId == null || !pagamentoAutorizadoId.matches("[0-9]+")) {
            throw new IllegalArgumentException("Identificador da cobrança autorizada inválido.");
        }
        try {
            JsonNode resposta = interpretarResposta(cliente.get()
                    .uri("/authorized_payments/{id}", pagamentoAutorizadoId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .retrieve()
                    .body(String.class));
            if (!pagamentoAutorizadoId.equals(resposta.path("id").asText())) {
                throw new MercadoPagoException("Identificador da cobrança autorizada inconsistente.", null);
            }
            return resposta;
        } catch (RestClientResponseException e) {
            throw erroHttp("consultar cobrança autorizada", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode listarPagamentosAutorizados(String assinaturaId, int limite, int deslocamento) {
        validarConfiguracaoAssinaturas();
        validarIdentificadorAssinatura(assinaturaId);
        if (limite < 1 || limite > 100) {
            throw new IllegalArgumentException("O limite deve estar entre 1 e 100.");
        }
        if (deslocamento < 0) {
            throw new IllegalArgumentException("O deslocamento não pode ser negativo.");
        }
        try {
            JsonNode resposta = interpretarResposta(cliente.get()
                    .uri(construtor -> construtor.path("/authorized_payments/search")
                            .queryParam("preapproval_id", assinaturaId)
                            .queryParam("offset", deslocamento)
                            .build())
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .retrieve()
                    .body(String.class));
            if (!resposta.path("results").isArray()) {
                throw new MercadoPagoException("A listagem de mensalidades retornou dados inesperados.", null);
            }
            JsonNode resultados = resposta.path("results");
            if (resultados.size() > limite) {
                throw new MercadoPagoException("A listagem de mensalidades excedeu o limite solicitado.", null);
            }
            return resposta;
        } catch (RestClientResponseException e) {
            throw erroHttp("listar mensalidades recorrentes", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode atualizarValorAssinaturaRecorrente(String assinaturaId, BigDecimal novoValorMensal) {
        validarConfiguracaoAssinaturas();
        validarIdentificadorAssinatura(assinaturaId);
        validarValor(novoValorMensal);

        Map<String, Object> recorrencia = new LinkedHashMap<>();
        recorrencia.put("transaction_amount", novoValorMensal.setScale(2, RoundingMode.UNNECESSARY));

        try {
            return interpretarResposta(cliente.put()
                    .uri("/preapproval/{id}", assinaturaId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("auto_recurring", recorrencia))
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("atualizar valor da assinatura recorrente", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    public JsonNode cancelarAssinaturaRecorrente(String assinaturaId) {
        validarConfiguracaoAssinaturas();
        validarIdentificadorAssinatura(assinaturaId);
        try {
            return interpretarResposta(cliente.put()
                    .uri("/preapproval/{id}", assinaturaId)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + subscriptionsAccessToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("status", "cancelled"))
                    .retrieve()
                    .body(String.class));
        } catch (RestClientResponseException e) {
            throw erroHttp("cancelar assinatura recorrente", e);
        } catch (RestClientException e) {
            throw erroComunicacao();
        }
    }

    private void validarIdentificadorAssinatura(String assinaturaId) {
        if (assinaturaId == null || !assinaturaId.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new IllegalArgumentException("Identificador da assinatura inválido.");
        }
    }

    private void validarValor(BigDecimal valor) {
        if (valor == null || valor.signum() <= 0 || valor.scale() > 2 || valor.precision() > 15) {
            throw new IllegalArgumentException("Valor inválido.");
        }
    }

    private void validarTexto(String valor, String mensagem) {
        if (valor == null || valor.isBlank() || valor.length() > 500) {
            throw new IllegalArgumentException(mensagem);
        }
    }

    private void validarUrlHttps(String url) {
        validarTexto(url, "URL de retorno obrigatória.");
        try {
            URI uri = URI.create(url.trim());
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                    || uri.getUserInfo() != null || uri.getFragment() != null
                    || uri.getPort() < -1 || url.length() > 2048) {
                throw new IllegalArgumentException("A URL de retorno deve ser HTTPS válida.");
            }
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("A URL de retorno deve ser HTTPS válida.");
        }
    }

    private JsonNode interpretarResposta(String resposta) {
        if (resposta == null || resposta.isBlank()) {
            throw new MercadoPagoException("O Mercado Pago retornou uma resposta vazia.", null);
        }
        try {
            JsonNode dados = objectMapper.readTree(resposta);
            if (!dados.isObject() || dados.isEmpty()) {
                throw new MercadoPagoException("O Mercado Pago retornou dados inesperados.", null);
            }
            return dados;
        } catch (JsonProcessingException e) {
            throw new MercadoPagoException("Não foi possível interpretar a resposta do Mercado Pago.", null);
        }
    }

    private void validarConfiguracaoAssinaturas() {
        if (subscriptionsAccessToken.isBlank()) {
            throw new MercadoPagoException("As assinaturas do Mercado Pago ainda não estão configuradas no servidor.", null);
        }
    }

    private void validarConfiguracao() {
        if (accessToken.isBlank()) {
            throw new MercadoPagoException("O Mercado Pago ainda não está configurado no servidor.", null);
        }
    }

    private MercadoPagoException erroHttp(String operacao, RestClientResponseException e) {
        int codigo = e.getStatusCode().value();

        String erroApi = "";
        String mensagemApi = "";

        try {
            JsonNode resposta = objectMapper.readTree(e.getResponseBodyAsString());

            erroApi = resposta.path("error").asText("");
            mensagemApi = resposta.path("message").asText("");
        } catch (JsonProcessingException ex) {
            mensagemApi = "Resposta de erro não disponível em JSON.";
        }

        System.err.println(
                "Mercado Pago - Operação: " + operacao
                        + " | HTTP original: " + codigo
                        + " | Erro: " + erroApi
                        + " | Mensagem: " + mensagemApi
                        + " | Content-Type: " + (e.getResponseHeaders() == null ? "não informado" : e.getResponseHeaders().getContentType())
                        + " | Corpo vazio: " + e.getResponseBodyAsString().isBlank()
        );

        String detalhe = switch (codigo) {
            case 400, 422 -> "A API rejeitou os dados enviados.";
            case 401, 403 -> "As credenciais não foram aceitas ou não possuem permissão.";
            case 404 -> "O recurso solicitado não foi encontrado.";
            case 409 -> "A API identificou um conflito na operação.";
            case 429 -> "O limite de requisições foi atingido.";
            default -> codigo >= 500
                    ? "O serviço externo apresentou uma falha temporária."
                    : "A operação foi recusada.";
        };

        return new MercadoPagoException(
                "Falha ao " + operacao + " no Mercado Pago (HTTP " + codigo + "). " + detalhe,
                codigo
        );
    }

    private MercadoPagoException erroComunicacao() {
        return new MercadoPagoException("Não foi possível comunicar com o Mercado Pago.", null);
    }

    public static class MercadoPagoException extends RuntimeException {
        private final Integer statusCode;

        public MercadoPagoException(String mensagem, Integer statusCode) {
            super(mensagem);
            this.statusCode = statusCode;
        }

        public Integer getStatusCode() {
            return statusCode;
        }
    }
}