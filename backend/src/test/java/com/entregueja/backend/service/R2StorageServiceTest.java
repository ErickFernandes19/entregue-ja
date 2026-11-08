
package com.entregueja.backend.service;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import static org.junit.jupiter.api.Assertions.*;

class R2StorageServiceTest {

    @Test
    void testarConexaoComR2() throws Exception {

        String accountId = obrigatoria("R2_ACCOUNT_ID");
        String accessKey = obrigatoria("R2_ACCESS_KEY_ID");
        String secretKey = obrigatoria("R2_SECRET_ACCESS_KEY");

        String bucket = System.getenv("R2_BUCKET_NAME");

        if (bucket == null || bucket.isBlank()) {
            bucket = "entregueja-arquivos";
        }

        R2StorageService service = new R2StorageService(
                accountId,
                accessKey,
                secretKey,
                bucket
        );

        // PNG mínimo de 1 pixel para testar o upload.
        byte[] imagem = java.util.Base64.getDecoder().decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII="
        );

        MockMultipartFile arquivo = new MockMultipartFile(
                "foto",
                "teste-r2.png",
                "image/png",
                imagem
        );

        String chave = null;

        try {
            chave = service.enviarImagem(
                    arquivo,
                    "testes"
            );

            System.out.println("Upload realizado: " + chave);

            byte[] imagemRecuperada = service.buscarImagem(chave);

            assertArrayEquals(imagem, imagemRecuperada);

            System.out.println("Download realizado com sucesso!");
            System.out.println("Conteúdo verificado com sucesso!");

        } finally {
            if (chave != null) {
                service.excluirImagem(chave);
                System.out.println("Arquivo de teste excluído!");
            }

            service.fechar();
        }
    }

    private String obrigatoria(String nome) {
        String valor = System.getenv(nome);

        if (valor == null || valor.isBlank()) {
            throw new IllegalStateException(
                    "Variável de ambiente não configurada: " + nome
            );
        }

        return valor;
    }
}
