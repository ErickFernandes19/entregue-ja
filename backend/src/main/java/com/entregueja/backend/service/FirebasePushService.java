package com.entregueja.backend.service;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class FirebasePushService {

    private static final Logger logger = LoggerFactory.getLogger(FirebasePushService.class);

    private final NotificacaoService notificacaoService;

    public FirebasePushService(NotificacaoService notificacaoService) {
        this.notificacaoService = notificacaoService;
    }

    public int enviarParaConta(
            String tipoConta,
            Long contaId,
            String tipo,
            String titulo,
            String mensagem,
            Long entregaId
    ) {
        if (FirebaseApp.getApps().isEmpty()) {
            logger.debug("Envio de push ignorado: Firebase Admin não está configurado.");
            return 0;
        }

        if (tipo == null || tipo.isBlank()
                || titulo == null || titulo.isBlank()
                || mensagem == null || mensagem.isBlank()) {
            throw new IllegalArgumentException("Dados da notificação push inválidos");
        }

        List<String> tokens = notificacaoService.listarTokens(tipoConta, contaId);
        int enviados = 0;

        for (String token : tokens) {
            Message.Builder builder = Message.builder()
                    .setToken(token)
                    .setNotification(Notification.builder()
                            .setTitle(titulo)
                            .setBody(mensagem)
                            .build())
                    .putData("tipo", tipo)
                    .putData("tipoConta", tipoConta);

            if (entregaId != null) {
                builder.putData("entregaId", entregaId.toString());
            }

            try {
                FirebaseMessaging.getInstance().send(builder.build());
                enviados++;
            } catch (FirebaseMessagingException e) {
                logger.warn("Falha ao enviar notificação push: {}", e.getMessagingErrorCode());
            } catch (RuntimeException e) {
                logger.error("Falha inesperada ao enviar notificação push", e);
            }
        }

        return enviados;
    }
}
