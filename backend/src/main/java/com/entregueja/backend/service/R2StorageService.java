
package com.entregueja.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import jakarta.annotation.PreDestroy;

import java.io.IOException;
import java.net.URI;
import java.util.UUID;

@Service
public class R2StorageService {

    private final S3Client s3Client;
    private final String bucket;

    public R2StorageService(
            @Value("${cloudflare.r2.account-id}") String accountId,
            @Value("${cloudflare.r2.access-key}") String accessKey,
            @Value("${cloudflare.r2.secret-key}") String secretKey,
            @Value("${cloudflare.r2.bucket}") String bucket
    ) {
        this.bucket = bucket;

        AwsBasicCredentials credentials =
                AwsBasicCredentials.create(accessKey, secretKey);

        this.s3Client = S3Client.builder()
                .endpointOverride(
                        URI.create(
                                "https://" + accountId +
                                        ".r2.cloudflarestorage.com"
                        )
                )
                .credentialsProvider(
                        StaticCredentialsProvider.create(credentials)
                )
                .region(Region.of("auto"))
                .build();
    }

    public String enviarImagem(
            MultipartFile arquivo,
            String pasta
    ) throws IOException {

        if (arquivo == null || arquivo.isEmpty()) {
            throw new IllegalArgumentException(
                    "Nenhuma imagem foi enviada."
            );
        }

        String contentType = arquivo.getContentType();

        if (contentType == null ||
                !(contentType.equals("image/jpeg") ||
                        contentType.equals("image/png") ||
                        contentType.equals("image/webp"))) {
            throw new IllegalArgumentException(
                    "Formato de imagem não permitido."
            );
        }

        if (arquivo.getSize() > 10 * 1024 * 1024) {
            throw new IllegalArgumentException(
                    "A imagem deve ter no máximo 10 MB."
            );
        }

        String extensao = switch (contentType) {
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> ".jpg";
        };

        String chave = pasta + "/" +
                UUID.randomUUID() + extensao;

        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(bucket)
                        .key(chave)
                        .contentType(contentType)
                        .build(),
                RequestBody.fromBytes(arquivo.getBytes())
        );

        return chave;
    }

    public byte[] buscarImagem(String chave) {
        return s3Client.getObjectAsBytes(
                GetObjectRequest.builder()
                        .bucket(bucket)
                        .key(chave)
                        .build()
        ).asByteArray();
    }

    public void excluirImagem(String chave) {
        s3Client.deleteObject(
                DeleteObjectRequest.builder()
                        .bucket(bucket)
                        .key(chave)
                        .build()
        );
    }

    @PreDestroy
    public void fechar() {
        s3Client.close();
    }
}
