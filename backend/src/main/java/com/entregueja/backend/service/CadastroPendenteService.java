
package com.entregueja.backend.service;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Locale;
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
        validarTipo(tipo);

        if (nome == null || nome.isBlank()
                || email == null || email.isBlank()
                || senha == null || senha.isBlank()) {
            throw new IllegalArgumentException("Preencha todos os campos");
        }

        if (!senhaForte(senha)) {
            throw new IllegalArgumentException(
                    "A senha deve ter pelo menos 8 caracteres, incluindo letra maiúscula, minúscula, número e caractere especial"
            );
        }

        String emailNormalizado = normalizarEmail(email);
        String chave = tipo + ":" + emailNormalizado;

        CadastroPendente existente = cadastros.get(chave);
        validarIntervaloEnvio(existente);

        String codigo = gerarCodigo();
        LocalDateTime agora = LocalDateTime.now();

        CadastroPendente pendente = new CadastroPendente(
                nome.trim(),
                emailNormalizado,
                passwordEncoder.encode(senha),
                passwordEncoder.encode(codigo),
                agora.plusMinutes(VALIDADE_MINUTOS),
                agora
        );

        emailService.enviarCodigoVerificacaoCadastro(
                emailNormalizado,
                codigo
        );

        cadastros.put(chave, pendente);
    }

    public synchronized void reenviarCodigo(
            String tipo,
            String email
    ) {
        validarTipo(tipo);

        if (email == null || email.isBlank()) {
            throw new IllegalArgumentException("Informe o e-mail");
        }

        String emailNormalizado = normalizarEmail(email);
        String chave = tipo + ":" + emailNormalizado;

        CadastroPendente pendente = cadastros.get(chave);

        if (pendente == null) {
            throw new IllegalArgumentException(
                    "Cadastro pendente não encontrado. Inicie o cadastro novamente"
            );
        }

        validarIntervaloEnvio(pendente);

        String codigo = gerarCodigo();
        LocalDateTime agora = LocalDateTime.now();

        CadastroPendente atualizado = new CadastroPendente(
                pendente.nome,
                pendente.email,
                pendente.senhaHash,
                passwordEncoder.encode(codigo),
                agora.plusMinutes(VALIDADE_MINUTOS),
                agora
        );

        emailService.enviarCodigoVerificacaoCadastro(
                emailNormalizado,
                codigo
        );

        cadastros.put(chave, atualizado);
    }

    public synchronized DadosCadastro confirmarCodigo(
            String tipo,
            String email,
            String codigo
    ) {
        validarTipo(tipo);

        if (email == null || email.isBlank()
                || codigo == null || codigo.isBlank()) {
            throw new IllegalArgumentException(
                    "Informe o e-mail e o código"
            );
        }

        String chave = tipo + ":" + normalizarEmail(email);
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
                    "Limite de tentativas excedido. Inicie o cadastro novamente"
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
                        "Limite de tentativas excedido. Inicie o cadastro novamente"
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

    private void validarTipo(String tipo) {
        if (!"ENTREGADOR".equals(tipo) && !"EMPRESA".equals(tipo)) {
            throw new IllegalArgumentException("Tipo de cadastro inválido");
        }
    }

    private String normalizarEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private boolean senhaForte(String senha) {
        return senha != null
                && senha.length() >= 8
                && senha.matches("(?s).*[A-Z].*")
                && senha.matches("(?s).*[a-z].*")
                && senha.matches("(?s).*[0-9].*")
                && senha.matches("(?s).*[^A-Za-z0-9].*");
    }

    private void validarIntervaloEnvio(CadastroPendente pendente) {
        if (pendente == null) {
            return;
        }

        if (LocalDateTime.now().isBefore(
                pendente.ultimoEnvio.plusSeconds(
                        INTERVALO_REENVIO_SEGUNDOS
                )
        )) {
            throw new IllegalArgumentException(
                    "Aguarde 60 segundos antes de solicitar outro código"
            );
        }
    }

    private String gerarCodigo() {
        return String.format(
                Locale.ROOT,
                "%06d",
                secureRandom.nextInt(1000000)
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
