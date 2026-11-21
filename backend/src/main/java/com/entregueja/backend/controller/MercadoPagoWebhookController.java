package com.entregueja.backend.controller;

import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.service.PagamentoAssinaturaService;
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

    private final String webhookSecret;
    private final PagamentoAssinaturaRepository pagamentoRepository;
    private final PagamentoAssinaturaService pagamentoService;

    public MercadoPagoWebhookController(
            @Value("${mercadopago.webhook-secret:}") String webhookSecret,
            PagamentoAssinaturaRepository pagamentoRepository,
            PagamentoAssinaturaService pagamentoService
    ) {
        this.webhookSecret = webhookSecret == null ? "" : webhookSecret.trim();
        this.pagamentoRepository = pagamentoRepository;
        this.pagamentoService = pagamentoService;
    }

    @PostMapping("/webhook")
    public ResponseEntity<Void> receberNotificacao(
            @RequestHeader(value = "x-signature", required = false) String assinatura,
            @RequestHeader(value = "x-request-id", required = false) String requestId,
            @RequestParam Map<String, String> parametros,
            @RequestBody(required = false) JsonNode corpo
    ) {
        if (webhookSecret.isBlank()) {
            LOGGER.error("Segredo do webhook do Mercado Pago não configurado");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
        }

        String idUrl = parametros.get("data.id");
        String idCorpo = texto(corpo == null ? null : corpo.path("data"), "id");
        if (idUrl != null && !idUrl.isBlank() && idCorpo != null && !idUrl.equalsIgnoreCase(idCorpo)) {
            LOGGER.warn("Webhook com identificadores divergentes");
            return ResponseEntity.badRequest().build();
        }

        String dataId = idUrl != null && !idUrl.isBlank() ? idUrl : idCorpo;
        if (!assinaturaValida(assinatura, requestId, dataId)) {
            LOGGER.warn("Webhook com assinatura inválida");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String tipoUrl = parametros.get("type");
        String tipoCorpo = texto(corpo, "type");
        if (tipoUrl != null && !tipoUrl.isBlank() && tipoCorpo != null
                && !tipoUrl.equalsIgnoreCase(tipoCorpo)) {
            LOGGER.warn("Webhook com tipos de evento divergentes");
            return ResponseEntity.badRequest().build();
        }

        String tipo = tipoUrl != null && !tipoUrl.isBlank() ? tipoUrl : tipoCorpo;
        if (!"payment".equalsIgnoreCase(tipo)) {
            return ResponseEntity.ok().build();
        }

        if (dataId == null || !dataId.matches("[0-9]+")) {
            return ResponseEntity.badRequest().build();
        }

        try {
            PagamentoAssinatura pagamento = pagamentoRepository.findByMercadoPagoPagamentoId(dataId).orElse(null);
            if (pagamento != null && pagamento.getFormaPagamento() == PagamentoAssinatura.FormaPagamento.PIX) {
                pagamentoService.consultarCobrancaPix(pagamento.getEmpresaId(), pagamento.getId());
            } else {
                pagamentoService.processarPagamentoRecorrente(dataId);
            }
            return ResponseEntity.ok().build();
        } catch (RuntimeException e) {
            LOGGER.error("Falha ao processar webhook de pagamento do Mercado Pago, id={}", dataId, e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    private boolean assinaturaValida(String assinatura, String requestId, String dataId) {
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
            mac.init(new SecretKeySpec(webhookSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] calculado = mac.doFinal(manifesto.getBytes(StandardCharsets.UTF_8));
            byte[] recebido = HexFormat.of().parseHex(hashRecebido);
            return MessageDigest.isEqual(calculado, recebido);
        } catch (Exception e) {
            return false;
        }
    }

    private String texto(JsonNode objeto, String campo) {
        if (objeto == null) return null;
        JsonNode valor = objeto.path(campo);
        if (valor.isMissingNode() || valor.isNull() || valor.isContainerNode()) return null;
        String resultado = valor.asText();
        return resultado.isBlank() ? null : resultado;
    }
}
