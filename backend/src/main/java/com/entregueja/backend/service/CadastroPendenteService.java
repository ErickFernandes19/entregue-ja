
package com.entregueja.backend.service;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class CadastroPendenteService {

    private static final int VALIDADE_MINUTOS = 10;
    private static final int INTERVALO_REENVIO_SEGUNDOS = 60;
    private static final int MAX_TENTATIVAS = 5;

    private final Map<String, CadastroPendente> cadastros =
            new ConcurrentHashMap<>();

    private final SecureRandom secureRandom = new SecureRandom();
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;

    public CadastroPendenteService(
            PasswordEncoder passwordEncoder,
            EmailService emailService
    ) {
        this.passwordEncoder = passwordEncoder;
        this.emailService = emailService;
    }

    public synchronized void solicitarCadastro(
            String tipo,
            String nome,
            String email,
            String senha
    ) {
        if (!"ENTREGADOR".equals(tipo) && !"EMPRESA".equals(tipo)) {
            throw new IllegalArgumentException("Tipo de cadastro inválido");
        }

        if (nome == null || nome.isBlank()
                || email == null || email.isBlank()
                || senha == null || senha.isBlank()) {
            throw new IllegalArgumentException("Preencha todos os campos");
        }

        if (senha.length() < 6) {
            throw new IllegalArgumentException(
                    "A senha deve possuir pelo menos 6 caracteres"
            );
        }

        String emailNormalizado = email.trim().toLowerCase();
        String chave = tipo + ":" + emailNormalizado;

        CadastroPendente existente = cadastros.get(chave);

        if (existente != null
                && LocalDateTime.now().isBefore(
                existente.ultimoEnvio.plusSeconds(
                        INTERVALO_REENVIO_SEGUNDOS
                )
        )) {
            throw new IllegalArgumentException(
                    "Aguarde 60 segundos antes de solicitar outro código"
            );
        }

        String codigo = String.format(
                "%06d",
                secureRandom.nextInt(1000000)
        );

        CadastroPendente pendente = new CadastroPendente(
                nome.trim(),
                emailNormalizado,
                passwordEncoder.encode(senha),
                passwordEncoder.encode(codigo),
                LocalDateTime.now().plusMinutes(VALIDADE_MINUTOS),
                LocalDateTime.now()
        );

        emailService.enviarCodigoVerificacaoCadastro(
                emailNormalizado,
                codigo
        );

        cadastros.put(chave, pendente);
    }

    public synchronized DadosCadastro confirmarCodigo(
            String tipo,
            String email,
            String codigo
    ) {
        if (tipo == null || email == null || codigo == null) {
            throw new IllegalArgumentException(
                    "Informe o e-mail e o código"
            );
        }

        String chave = tipo + ":" + email.trim().toLowerCase();
        CadastroPendente pendente = cadastros.get(chave);

        if (pendente == null) {
            throw new IllegalArgumentException(
                    "Cadastro não encontrado ou expirado"
            );
        }

        if (LocalDateTime.now().isAfter(pendente.expiraEm)) {
            cadastros.remove(chave);
            throw new IllegalArgumentException(
                    "Código expirado. Solicite um novo código"
            );
        }

        if (pendente.tentativas >= MAX_TENTATIVAS) {
            cadastros.remove(chave);
            throw new IllegalArgumentException(
                    "Limite de tentativas excedido. Solicite outro código"
            );
        }

        if (!passwordEncoder.matches(
                codigo.trim(),
                pendente.codigoHash
        )) {
            pendente.tentativas++;

            if (pendente.tentativas >= MAX_TENTATIVAS) {
                cadastros.remove(chave);
                throw new IllegalArgumentException(
                        "Limite de tentativas excedido. Solicite outro código"
                );
            }

            throw new IllegalArgumentException("Código inválido");
        }

        cadastros.remove(chave);

        return new DadosCadastro(
                pendente.nome,
                pendente.email,
                pendente.senhaHash
        );
    }

    public record DadosCadastro(
            String nome,
            String email,
            String senhaHash
    ) {
    }

    private static class CadastroPendente {

        private final String nome;
        private final String email;
        private final String senhaHash;
        private final String codigoHash;
        private final LocalDateTime expiraEm;
        private final LocalDateTime ultimoEnvio;
        private int tentativas;

        private CadastroPendente(
                String nome,
                String email,
                String senhaHash,
                String codigoHash,
                LocalDateTime expiraEm,
                LocalDateTime ultimoEnvio
        ) {
            this.nome = nome;
            this.email = email;
            this.senhaHash = senhaHash;
            this.codigoHash = codigoHash;
            this.expiraEm = expiraEm;
            this.ultimoEnvio = ultimoEnvio;
            this.tentativas = 0;
        }
    }
}
