package com.entregueja.backend.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

@Configuration
public class FirebaseConfig {

    private static final Logger logger = LoggerFactory.getLogger(FirebaseConfig.class);

    @Value("${FIREBASE_SERVICE_ACCOUNT_JSON:}")
    private String credenciaisJson;

    @PostConstruct
    public void inicializar() {
        if (credenciaisJson == null || credenciaisJson.isBlank()) {
            logger.info("Firebase Admin desabilitado: FIREBASE_SERVICE_ACCOUNT_JSON não configurada.");
            return;
        }

        if (!FirebaseApp.getApps().isEmpty()) {
            return;
        }

        try (ByteArrayInputStream stream = new ByteArrayInputStream(
                credenciaisJson.getBytes(StandardCharsets.UTF_8))) {
            GoogleCredentials credentials = GoogleCredentials.fromStream(stream);
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(credentials)
                    .build();
            FirebaseApp.initializeApp(options);
            logger.info("Firebase Admin inicializado com sucesso.");
        } catch (Exception e) {
            logger.error("Não foi possível inicializar o Firebase Admin. O backend continuará sem envio de push.");
        }
    }
}
