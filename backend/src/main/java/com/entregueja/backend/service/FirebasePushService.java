package com.entregueja.backend.service;

import com.entregueja.backend.entity.PreferenciaNotificacao;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
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
    private final PreferenciaNotificacaoService preferenciaNotificacaoService;

    public FirebasePushService(
            NotificacaoService notificacaoService,
            PreferenciaNotificacaoService preferenciaNotificacaoService
    ) {
        this.notificacaoService = notificacaoService;
        this.preferenciaNotificacaoService = preferenciaNotificacaoService;
    }

    private String obterCanalNotificacao(String tipoConta, Long contaId) {
        PreferenciaNotificacao preferencias = preferenciaNotificacaoService.buscar(tipoConta, contaId);

        if (preferencias.isSons() && preferencias.isVibracao()) {
            return "entregue_ja_som_vibracao";
        }

        if (preferencias.isSons()) {
            return "entregue_ja_som_sem_vibracao";
        }

        if (preferencias.isVibracao()) {
            return "entregue_ja_silencioso_vibracao";
        }

        return "entregue_ja_silencioso_sem_vibracao";
    }

    public int enviarParaConta(
            String tipoConta,
            Long contaId,
            String tipo,
            String titulo,
            String mensagem,
            Long entregaId
    ) {
        if (tipo == null || tipo.isBlank()
                || titulo == null || titulo.isBlank()
                || mensagem == null || mensagem.isBlank()) {
            throw new IllegalArgumentException("Dados da notificação push inválidos");
        }

        if (!preferenciaNotificacaoService.permiteNotificacao(tipoConta, contaId, tipo)) {
            logger.debug(
                    "Notificação push ignorada pelas preferências da conta: tipo={}, contaId={}, notificacao={}",
                    tipoConta,
                    contaId,
                    tipo
            );
            return 0;
        }

        if (FirebaseApp.getApps().isEmpty()) {
            logger.debug("Envio de push ignorado: Firebase Admin não está configurado.");
            return 0;
        }

        List<String> tokens = notificacaoService.listarTokens(tipoConta, contaId);
        if (tokens.isEmpty()) {
            return 0;
        }

        String canal = obterCanalNotificacao(tipoConta, contaId);
        int enviados = 0;

        for (String token : tokens) {
            Message.Builder builder = Message.builder()
                    .setToken(token)
                    .setNotification(Notification.builder()
                            .setTitle(titulo)
                            .setBody(mensagem)
                            .build())
                    .setAndroidConfig(AndroidConfig.builder()
                            .setNotification(AndroidNotification.builder()
                                    .setChannelId(canal)
                                    .build())
                            .build())
                    .putData("tipo", tipo)
                    .putData("tipoConta", tipoConta)
                    .putData("contaId", contaId.toString());

            if (entregaId != null) {
                builder.putData("entregaId", entregaId.toString());
            }

            try {
                FirebaseMessaging.getInstance().send(builder.build());
                enviados++;
            } catch (FirebaseMessagingException e) {
                logger.warn(
                        "Falha ao enviar notificação push: tipo={}, contaId={}, erro={}",
                        tipoConta,
                        contaId,
                        e.getMessagingErrorCode()
                );
            } catch (RuntimeException e) {
                logger.error("Falha inesperada ao enviar notificação push", e);
            }
        }

        return enviados;
    }
}
