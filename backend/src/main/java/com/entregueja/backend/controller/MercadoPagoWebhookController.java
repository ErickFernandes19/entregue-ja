package com.entregueja.backend.controller;

import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.service.PagamentoAssinaturaService;
import com.entregueja.backend.service.AssinaturaRecorrenteService;
import com.entregueja.backend.service.MercadoPagoService;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Map;

@RestController
@RequestMapping("/pagamentos/assinaturas")
public class MercadoPagoWebhookController {

    private static final Logger LOGGER = LoggerFactory.getLogger(MercadoPagoWebhookController.class);
    private static final long JANELA_ASSINATURA_SEGUNDOS = 300;

    private final String webhookSecretPix;
    private final String webhookSecretAssinaturas;
    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final PagamentoAssinaturaService pagamentoService;
    private final AssinaturaRecorrenteService assinaturaRecorrenteService;
    private final MercadoPagoService mercadoPagoService;

    public MercadoPagoWebhookController(
            @Value("${mercadopago.webhook-secret:}") String webhookSecretPix,
            @Value("${MERCADOPAGO_SUBSCRIPTIONS_WEBHOOK_SECRET:}") String webhookSecretAssinaturas,
            PagamentoAssinaturaRepository pagamentoRepository,
            PagamentoAssinaturaService pagamentoService,
            AssinaturaRecorrenteService assinaturaRecorrenteService,
            MercadoPagoService mercadoPagoService
    ) {
        this.webhookSecretPix = webhookSecretPix == null ? "" : webhookSecretPix.trim();
        this.webhookSecretAssinaturas = webhookSecretAssinaturas == null ? "" : webhookSecretAssinaturas.trim();
        this.pagamentoRepository = pagamentoRepository;
        this.pagamentoService = pagamentoService;
        this.assinaturaRecorrenteService = assinaturaRecorrenteService;
        this.mercadoPagoService = mercadoPagoService;
    }

    @PostMapping("/webhook")
    public ResponseEntity<Void> receberNotificacaoPix(
            @RequestHeader(value = "x-signature", required = false) String assinatura,
            @RequestHeader(value = "x-request-id", required = false) String requestId,
            @RequestParam Map<String, String> parametros,
            @RequestBody(required = false) JsonNode corpo
    ) {
        return receberNotificacao(assinatura, requestId, parametros, corpo, webhookSecretPix, false);
    }

    @PostMapping("/webhook/recorrentes")
    public ResponseEntity<Void> receberNotificacaoRecorrente(
            @RequestHeader(value = "x-signature", required = false) String assinatura,
            @RequestHeader(value = "x-request-id", required = false) String requestId,
            @RequestParam Map<String, String> parametros,
            @RequestBody(required = false) JsonNode corpo
    ) {
        return receberNotificacao(assinatura, requestId, parametros, corpo, webhookSecretAssinaturas, true);
    }

    private ResponseEntity<Void> receberNotificacao(
            String assinatura,
            String requestId,
            Map<String, String> parametros,
            JsonNode corpo,
            String segredo,
            boolean recorrente
    ) {
        if (segredo.isBlank()) {
            LOGGER.error("Segredo do webhook do Mercado Pago não configurado, recorrente={}", recorrente);
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }

        String idUrl = parametros.get("data.id");
        String idCorpo = texto(corpo == null ? null : corpo.path("data"), "id");

        if (idUrl != null && !idUrl.isBlank()
                && idCorpo != null && !idUrl.equalsIgnoreCase(idCorpo)) {
            LOGGER.warn("Webhook com identificadores divergentes");
            return ResponseEntity.badRequest().build();
        }

        String dataId = idUrl != null && !idUrl.isBlank() ? idUrl : idCorpo;

        if (!assinaturaValida(assinatura, requestId, dataId, segredo)) {
            LOGGER.warn("Webhook com assinatura inválida, recorrente={}", recorrente);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String tipoUrl = parametros.get("type");
        String tipoCorpo = texto(corpo, "type");

        if (tipoUrl != null && !tipoUrl.isBlank()
                && tipoCorpo != null && !tipoUrl.equalsIgnoreCase(tipoCorpo)) {
            boolean eventoAssinaturaEquivalente = recorrente
                    && (("subscription_preapproval".equalsIgnoreCase(tipoUrl)
                    && "preapproval".equalsIgnoreCase(tipoCorpo))
                    || ("preapproval".equalsIgnoreCase(tipoUrl)
                    && "subscription_preapproval".equalsIgnoreCase(tipoCorpo)));

            if (!eventoAssinaturaEquivalente) {
                if (recorrente
                        && "subscription_authorized_payment".equalsIgnoreCase(tipoUrl)
                        && "subscription_preapproval".equalsIgnoreCase(tipoCorpo)) {
                    LOGGER.warn("Notificação de teste com tipos incompatíveis ignorada, tipoUrl={}, tipoCorpo={}", tipoUrl, tipoCorpo);
                    return ResponseEntity.ok().build();
                }
                LOGGER.warn("Webhook com tipos de evento divergentes, tipoUrl={}, tipoCorpo={}", tipoUrl, tipoCorpo);
                return ResponseEntity.badRequest().build();
            }
        }

        String tipo = tipoUrl != null && !tipoUrl.isBlank() ? tipoUrl : tipoCorpo;
        if (recorrente && "preapproval".equalsIgnoreCase(tipo)) {
            tipo = "subscription_preapproval";
        }

        if (tipo == null || tipo.isBlank()) {
            tipo = parametros.get("topic");
        }

        boolean eventoPagamentoAutorizado = recorrente && "subscription_authorized_payment".equalsIgnoreCase(tipo);
        boolean eventoPagamento = "payment".equalsIgnoreCase(tipo);
        boolean eventoAssinatura = "subscription_preapproval".equalsIgnoreCase(tipo);

        if (!eventoPagamento && !eventoPagamentoAutorizado && !(recorrente && eventoAssinatura)) {
            LOGGER.info("Evento do Mercado Pago ignorado, tipo={}, recorrente={}", tipo, recorrente);
            return ResponseEntity.ok().build();
        }

        if ((eventoPagamento || eventoPagamentoAutorizado)
                && (dataId == null || !dataId.matches("[0-9]+"))) {
            return ResponseEntity.badRequest().build();
        }

        if (eventoAssinatura && (dataId == null || !dataId.matches("[A-Za-z0-9_-]{1,100}"))) {
            return ResponseEntity.badRequest().build();
        }

        try {
            if (eventoAssinatura) {
                assinaturaRecorrenteService.sincronizarNotificacao(dataId);
                return ResponseEntity.ok().build();
            }

            if (eventoPagamentoAutorizado) {
                JsonNode autorizado = mercadoPagoService.consultarPagamentoAutorizado(dataId);
                String pagamentoId = texto(autorizado.path("payment"), "id");
                if (pagamentoId == null || !pagamentoId.matches("[0-9]+")) {
                    LOGGER.error("Cobrança autorizada sem ID de pagamento válido, id={}", dataId);
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
                }
                pagamentoService.processarPagamentoRecorrente(pagamentoId);
                return ResponseEntity.ok().build();
            }

            PagamentoAssinatura pagamento = pagamentoRepository
                    .findByMercadoPagoPagamentoId(dataId)
                    .orElse(null);

            if (recorrente) {
                if (pagamento != null && pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.CARTAO) {
                    LOGGER.warn("Pagamento Pix recebido no webhook de assinaturas, id={}", dataId);
                    return ResponseEntity.badRequest().build();
                }
                pagamentoService.processarPagamentoRecorrente(dataId);
            } else {
                if (pagamento == null) {
                    LOGGER.warn("Pagamento sem registro local recebido no webhook Pix, id={}", dataId);
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
                }
                if (pagamento.getFormaPagamento() != PagamentoAssinatura.FormaPagamento.PIX) {
                    LOGGER.warn("Pagamento não Pix recebido no webhook Pix, id={}", dataId);
                    return ResponseEntity.badRequest().build();
                }
                pagamentoService.consultarCobrancaPix(pagamento.getEmpresaId(), pagamento.getId());
            }

            return ResponseEntity.ok().build();
        } catch (RuntimeException e) {
            LOGGER.error("Falha ao processar webhook do Mercado Pago, id={}, recorrente={}", dataId, recorrente, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    private boolean assinaturaValida(String assinatura, String requestId, String dataId, String segredo) {
        if (assinatura == null || requestId == null || requestId.isBlank()
                || dataId == null || dataId.isBlank()) {
            return false;
        }

        Map<String, String> partes = new HashMap<>();
        for (String item : assinatura.split(",")) {
            String[] par = item.trim().split("=", 2);
            if (par.length == 2) {
                partes.put(par[0].trim(), par[1].trim());
            }
        }

        String timestamp = partes.get("ts");
        String hashRecebido = partes.get("v1");

        if (timestamp == null || !timestamp.matches("[0-9]{1,20}")
                || hashRecebido == null || !hashRecebido.matches("(?i)[0-9a-f]{64}")) {
            return false;
        }

        try {
            long segundos = Long.parseLong(timestamp);
            long agora = Instant.now().getEpochSecond();
            if (segundos < agora - JANELA_ASSINATURA_SEGUNDOS
                    || segundos > agora + JANELA_ASSINATURA_SEGUNDOS) {
                return false;
            }

            String manifesto = "id:" + dataId.toLowerCase(Locale.ROOT)
                    + ";request-id:" + requestId
                    + ";ts:" + timestamp + ";";

            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(segredo.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] calculado = mac.doFinal(manifesto.getBytes(StandardCharsets.UTF_8));
            byte[] recebido = HexFormat.of().parseHex(hashRecebido);
            return MessageDigest.isEqual(calculado, recebido);
        } catch (Exception e) {
            return false;
        }
    }

    private String texto(JsonNode objeto, String campo) {
        if (objeto == null) {
            return null;
        }
        JsonNode valor = objeto.path(campo);
        if (valor.isMissingNode() || valor.isNull() || valor.isContainerNode()) {
            return null;
        }
        String resultado = valor.asText();
        return resultado.isBlank() ? null : resultado;
    }
}
