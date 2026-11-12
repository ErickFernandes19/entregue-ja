
package com.entregueja.backend.service;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class RecuperacaoSenhaService {

    private static final Duration VALIDADE_CODIGO = Duration.ofMinutes(10);
    private static final Duration INTERVALO_SOLICITACAO = Duration.ofSeconds(60);
    private static final int MAX_TENTATIVAS = 5;

    private final EmailService emailService;
    private final PasswordEncoder passwordEncoder;
    private final SecureRandom secureRandom = new SecureRandom();

    private final Map<String, RecuperacaoPendente> recuperacoes =
            new ConcurrentHashMap<>();

    public RecuperacaoSenhaService(
            EmailService emailService,
            PasswordEncoder passwordEncoder
    ) {
        this.emailService = emailService;
        this.passwordEncoder = passwordEncoder;
    }

    public void solicitarCodigo(String tipo, String email) {
        String chave = criarChave(tipo, email);
        Instant agora = Instant.now();

        RecuperacaoPendente anterior = recuperacoes.get(chave);

        if (anterior != null
                && Duration.between(
                anterior.ultimaSolicitacao,
                agora
        ).compareTo(INTERVALO_SOLICITACAO) < 0) {
            throw new IllegalArgumentException(
                    "Aguarde 60 segundos antes de solicitar outro código."
            );
        }

        String codigo = String.format(
                "%06d",
                secureRandom.nextInt(1_000_000)
        );

        RecuperacaoPendente pendente = new RecuperacaoPendente(
                passwordEncoder.encode(codigo),
                agora.plus(VALIDADE_CODIGO),
                agora
        );

        recuperacoes.put(chave, pendente);

        try {
            emailService.enviarCodigoRecuperacao(email, codigo);
        } catch (RuntimeException e) {
            recuperacoes.remove(chave, pendente);
            throw e;
        }
    }

    public void validarCodigo(
            String tipo,
            String email,
            String codigo
    ) {
        String chave = criarChave(tipo, email);

        RecuperacaoPendente pendente = recuperacoes.get(chave);

        if (pendente == null) {
            throw new IllegalArgumentException(
                    "Código não encontrado. Solicite um novo código."
            );
        }

        synchronized (pendente) {
            if (Instant.now().isAfter(pendente.expiracao)) {
                recuperacoes.remove(chave, pendente);
                throw new IllegalArgumentException(
                        "Código expirado. Solicite um novo código."
                );
            }

            if (pendente.tentativas >= MAX_TENTATIVAS) {
                recuperacoes.remove(chave, pendente);
                throw new IllegalArgumentException(
                        "Limite de tentativas atingido."
                );
            }

            if (codigo == null
                    || !codigo.matches("\\d{6}")
                    || !passwordEncoder.matches(
                    codigo,
                    pendente.codigoHash
            )) {
                pendente.tentativas++;

                if (pendente.tentativas >= MAX_TENTATIVAS) {
                    recuperacoes.remove(chave, pendente);
                    throw new IllegalArgumentException(
                            "Limite de tentativas atingido."
                    );
                }

                throw new IllegalArgumentException(
                        "Código de recuperação inválido."
                );
            }
        }
    }

    public void consumirCodigo(
            String tipo,
            String email,
            String codigo,
            Runnable atualizarSenha
    ) {
        String chave = criarChave(tipo, email);

        RecuperacaoPendente pendente = recuperacoes.get(chave);

        if (pendente == null) {
            throw new IllegalArgumentException(
                    "Código não encontrado. Solicite um novo código."
            );
        }

        synchronized (pendente) {
            if (recuperacoes.get(chave) != pendente) {
                throw new IllegalArgumentException(
                        "Código não encontrado. Solicite um novo código."
                );
            }

            validarCodigo(tipo, email, codigo);
            atualizarSenha.run();
            recuperacoes.remove(chave, pendente);
        }
    }

    private String criarChave(String tipo, String email) {
        if (tipo == null || email == null
                || tipo.isBlank() || email.isBlank()) {
            throw new IllegalArgumentException(
                    "Tipo de conta e e-mail são obrigatórios."
            );
        }

        return tipo.trim().toUpperCase()
                + ":"
                + email.trim().toLowerCase(java.util.Locale.ROOT);
    }

    private static class RecuperacaoPendente {

        private final String codigoHash;
        private final Instant expiracao;
        private final Instant ultimaSolicitacao;
        private int tentativas;

        private RecuperacaoPendente(
                String codigoHash,
                Instant expiracao,
                Instant ultimaSolicitacao
        ) {
            this.codigoHash = codigoHash;
            this.expiracao = expiracao;
            this.ultimaSolicitacao = ultimaSolicitacao;
            this.tentativas = 0;
        }
    }
}
