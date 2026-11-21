package com.entregueja.backend.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

@Service
public class EmailService {

    private static final URI BREVO_URL = URI.create("https://api.brevo.com/v3/smtp/email");

    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final String apiKey;
    private final String remetente;

    public EmailService(
            ObjectMapper objectMapper,
            @Value("${BREVO_API_KEY:}") String apiKey,
            @Value("${BREVO_SENDER_EMAIL:}") String remetente
    ) {
        this.objectMapper = objectMapper;
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.remetente = remetente == null ? "" : remetente.trim();
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    public void enviarCodigoRecuperacao(String destinatario, String codigo) {
        String texto = "Olá!\n\n"
                + "Recebemos uma solicitação para redefinir sua senha no Entregue Já.\n\n"
                + "Seu código de recuperação é:\n\n"
                + codigo
                + "\n\nEste código é válido por 10 minutos.\n\n"
                + "Se você não solicitou a recuperação de senha, ignore este e-mail.";

        enviarEmail(destinatario, "Entregue Já - Recuperação de senha", texto);
    }

    public void enviarCodigoVerificacaoCadastro(String destinatario, String codigo) {
        String texto = "Olá!\n\n"
                + "Recebemos uma solicitação de cadastro no Entregue Já.\n\n"
                + "Para confirmar seu endereço de e-mail, utilize o código:\n\n"
                + codigo
                + "\n\nEste código é válido por 10 minutos.\n\n"
                + "Sua conta só será criada após a confirmação do código.\n\n"
                + "Se você não solicitou este cadastro, ignore este e-mail.";

        enviarEmail(destinatario, "Entregue Já - Verificação de cadastro", texto);
    }

    private void enviarEmail(String destinatario, String assunto, String texto) {
        if (apiKey.isBlank() || remetente.isBlank()) {
            throw new IllegalStateException("O serviço de e-mail não está configurado. Configure BREVO_API_KEY e BREVO_SENDER_EMAIL.");
        }
        if (destinatario == null || destinatario.isBlank()) {
            throw new IllegalArgumentException("Destinatário de e-mail obrigatório.");
        }

        String corpo;
        try {
            corpo = objectMapper.writeValueAsString(Map.of(
                    "sender", Map.of("name", "Entregue Já", "email", remetente),
                    "to", new Object[]{Map.of("email", destinatario.trim())},
                    "subject", assunto,
                    "textContent", texto
            ));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Não foi possível preparar o e-mail.", e);
        }

        HttpRequest requisicao = HttpRequest.newBuilder(BREVO_URL)
                .timeout(Duration.ofSeconds(20))
                .header("accept", "application/json")
                .header("api-key", apiKey)
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(corpo))
                .build();

        try {
            HttpResponse<String> resposta = httpClient.send(
                    requisicao,
                    HttpResponse.BodyHandlers.ofString()
            );

            if (resposta.statusCode() < 200 || resposta.statusCode() >= 300) {
                throw new IllegalStateException(
                        "Falha ao enviar e-mail pelo Brevo. Status HTTP: " + resposta.statusCode() + "."
                );
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Envio de e-mail interrompido.", e);
        } catch (IOException e) {
            throw new IllegalStateException("Falha de comunicação com o Brevo.", e);
        }
    }
}
