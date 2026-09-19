package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.UsuarioRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.entregueja.backend.service.EmailService;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/auth")
@CrossOrigin(origins = "*")
public class AuthController {

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;

    public AuthController(
            UsuarioRepository usuarioRepository,
            PasswordEncoder passwordEncoder,
            EmailService emailService
    ) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
        this.emailService = emailService;
    }

    @PostMapping("/esqueci-senha")
    public ResponseEntity<?> esqueciSenha(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");

        if (email == null || email.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Informe o e-mail"
                    )
            );
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(email.trim());

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.ok(
                    Map.of(
                            "mensagem",
                            "Se o e-mail estiver cadastrado, um código será enviado"
                    )
            );
        }

        Usuario usuario = usuarioOptional.get();

        String codigo = String.format(
                "%06d",
                new java.security.SecureRandom()
                        .nextInt(1000000)
        );

        usuario.setCodigoRecuperacao(codigo);

        usuario.setCodigoRecuperacaoExpira(
                LocalDateTime.now().plusMinutes(10)
        );

        usuarioRepository.save(usuario);

        try {
            emailService.enviarCodigoRecuperacao(
                    usuario.getEmail(),
                    codigo
            );
        } catch (Exception e) {
            usuario.setCodigoRecuperacao(null);
            usuario.setCodigoRecuperacaoExpira(null);

            usuarioRepository.save(usuario);

            return ResponseEntity
                    .internalServerError()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Não foi possível enviar o e-mail de recuperação"
                            )
                    );
        }

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Código de recuperação enviado para o e-mail"
                )
        );
    }

    @PostMapping("/verificar-codigo")
    public ResponseEntity<?> verificarCodigo(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");
        String codigo = body.get("codigo");

        if (email == null
                || email.trim().isEmpty()
                || codigo == null
                || codigo.trim().isEmpty()) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Informe o e-mail e o código"
                    )
            );
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(email.trim());

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido ou expirado"
                    )
            );
        }

        Usuario usuario = usuarioOptional.get();

        if (usuario.getCodigoRecuperacao() == null
                || usuario.getCodigoRecuperacaoExpira() == null) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido ou expirado"
                    )
            );
        }

        if (LocalDateTime.now().isAfter(
                usuario.getCodigoRecuperacaoExpira()
        )) {
            usuario.setCodigoRecuperacao(null);
            usuario.setCodigoRecuperacaoExpira(null);

            usuarioRepository.save(usuario);

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código expirado"
                    )
            );
        }

        if (!usuario
                .getCodigoRecuperacao()
                .equals(codigo.trim())) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido"
                    )
            );
        }

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Código válido"
                )
        );
    }

    @PutMapping("/redefinir-senha")
    public ResponseEntity<?> redefinirSenha(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");
        String codigo = body.get("codigo");
        String novaSenha = body.get("novaSenha");

        if (email == null
                || email.trim().isEmpty()
                || codigo == null
                || codigo.trim().isEmpty()
                || novaSenha == null
                || novaSenha.isEmpty()) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Preencha todos os campos"
                    )
            );
        }

        if (novaSenha.length() < 6) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "A nova senha deve possuir pelo menos 6 caracteres"
                    )
            );
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(email.trim());

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido ou expirado"
                    )
            );
        }

        Usuario usuario = usuarioOptional.get();

        if (usuario.getCodigoRecuperacao() == null
                || usuario.getCodigoRecuperacaoExpira() == null) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido ou expirado"
                    )
            );
        }

        if (LocalDateTime.now().isAfter(
                usuario.getCodigoRecuperacaoExpira()
        )) {
            usuario.setCodigoRecuperacao(null);
            usuario.setCodigoRecuperacaoExpira(null);

            usuarioRepository.save(usuario);

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código expirado"
                    )
            );
        }

        if (!usuario
                .getCodigoRecuperacao()
                .equals(codigo.trim())) {

            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Código inválido"
                    )
            );
        }

        usuario.setSenha(
                passwordEncoder.encode(novaSenha)
        );

        usuario.setCodigoRecuperacao(null);
        usuario.setCodigoRecuperacaoExpira(null);

        usuarioRepository.save(usuario);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Senha redefinida com sucesso"
                )
        );
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, String> body) {
        String email = body.get("email");
        String senha = body.get("senha");

        if (email == null || email.trim().isEmpty()
                || senha == null || senha.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe e-mail e senha")
            );
        }

        var usuarioOptional = usuarioRepository.findByEmail(email.trim());

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.status(401).body(
                    Map.of("mensagem", "E-mail ou senha inválidos")
            );
        }

        Usuario usuario = usuarioOptional.get();

        if (!senhaValida(usuario.getSenha(), senha)) {
            return ResponseEntity.status(401).body(
                    Map.of("mensagem", "E-mail ou senha inválidos")
            );
        }

        if (!senhaEstaCriptografada(usuario.getSenha())) {
            usuario.setSenha(passwordEncoder.encode(senha));
            usuarioRepository.save(usuario);
        }

        Map<String, Object> resposta = new HashMap<>();

        resposta.put("mensagem", "Login realizado com sucesso");
        resposta.put("id", usuario.getId());
        resposta.put("nome", usuario.getNome());
        resposta.put("email", usuario.getEmail());
        resposta.put(
                "foto",
                usuario.getFoto() == null ? "" : usuario.getFoto()
        );

        return ResponseEntity.ok(resposta);
    }

    @GetMapping("/{email}/perfil")
    public ResponseEntity<?> perfil(@PathVariable String email) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    Map<String, Object> resposta = new HashMap<>();

                    resposta.put("id", usuario.getId());
                    resposta.put("nome", usuario.getNome());
                    resposta.put("email", usuario.getEmail());
                    resposta.put(
                            "veiculo",
                            usuario.getVeiculo() == null
                                    ? ""
                                    : usuario.getVeiculo()
                    );
                    resposta.put(
                            "capacidadeCarga",
                            usuario.getCapacidadeCarga() == null
                                    ? ""
                                    : usuario.getCapacidadeCarga()
                    );
                    resposta.put(
                            "foto",
                            usuario.getFoto() == null
                                    ? ""
                                    : usuario.getFoto()
                    );

                    return ResponseEntity.ok(resposta);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody Usuario usuario) {
        if (usuario.getNome() == null
                || usuario.getNome().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Nome é obrigatório")
            );
        }

        if (usuario.getEmail() == null
                || usuario.getEmail().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "E-mail é obrigatório")
            );
        }

        if (usuario.getSenha() == null
                || usuario.getSenha().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Senha é obrigatória")
            );
        }

        String email = usuario.getEmail().trim();

        if (usuarioRepository.findByEmail(email).isPresent()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "E-mail já cadastrado")
            );
        }

        usuario.setNome(usuario.getNome().trim());
        usuario.setEmail(email);
        usuario.setSenha(
                passwordEncoder.encode(usuario.getSenha())
        );

        usuarioRepository.save(usuario);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Usuário cadastrado com sucesso"
                )
        );
    }

    @PutMapping("/{email}/foto")
    public ResponseEntity<?> atualizarFotoUsuario(
            @PathVariable String email,
            @RequestParam("foto") MultipartFile foto
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    try {
                        String pasta = "uploads/usuarios/";

                        Files.createDirectories(
                                Paths.get(pasta)
                        );

                        String nomeArquivo =
                                email.replace("@", "_")
                                        .replace(".", "_")
                                        + "_"
                                        + System.currentTimeMillis()
                                        + "_"
                                        + foto.getOriginalFilename();

                        Path caminho = Paths.get(
                                pasta + nomeArquivo
                        );

                        Files.write(
                                caminho,
                                foto.getBytes()
                        );

                        String urlFoto =
                                "/uploads/usuarios/"
                                        + nomeArquivo;

                        usuario.setFoto(urlFoto);

                        usuarioRepository.save(usuario);

                        return ResponseEntity.ok(
                                Map.of(
                                        "mensagem",
                                        "Foto atualizada com sucesso",
                                        "foto",
                                        urlFoto
                                )
                        );
                    } catch (Exception e) {
                        return ResponseEntity
                                .internalServerError()
                                .body(
                                        Map.of(
                                                "mensagem",
                                                "Erro ao salvar foto"
                                        )
                                );
                    }
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @GetMapping("/{email}/empresa-vinculada")
    public ResponseEntity<?> empresaVinculada(
            @PathVariable String email
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    if (usuario.getEmpresa() == null) {
                        return ResponseEntity.ok(
                                Map.of(
                                        "vinculado",
                                        false
                                )
                        );
                    }

                    return ResponseEntity.ok(
                            Map.of(
                                    "vinculado",
                                    true,
                                    "nome",
                                    usuario.getEmpresa().getNome(),
                                    "email",
                                    usuario.getEmpresa().getEmail()
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @GetMapping("/{email}/vinculo-pendente")
    public ResponseEntity<?> vinculoPendente(
            @PathVariable String email
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    if (usuario.getEmpresaPendente() == null) {
                        return ResponseEntity.ok(
                                Map.of(
                                        "possuiVinculo",
                                        false
                                )
                        );
                    }

                    return ResponseEntity.ok(
                            Map.of(
                                    "possuiVinculo",
                                    true,
                                    "empresa",
                                    usuario.getEmpresaPendente().getNome(),
                                    "email",
                                    usuario.getEmpresaPendente().getEmail()
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PutMapping("/{email}/aceitar-vinculo")
    public ResponseEntity<?> aceitarVinculo(
            @PathVariable String email
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    if (usuario.getEmpresaPendente() == null) {
                        return ResponseEntity
                                .badRequest()
                                .build();
                    }

                    usuario.setEmpresa(
                            usuario.getEmpresaPendente()
                    );
                    usuario.setEmpresaPendente(null);
                    usuario.setDataVinculo(
                            LocalDateTime.now()
                    );

                    usuarioRepository.save(usuario);

                    return ResponseEntity.ok(
                            Map.of(
                                    "mensagem",
                                    "Vínculo aceito"
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PutMapping("/{email}/recusar-vinculo")
    public ResponseEntity<?> recusarVinculo(
            @PathVariable String email
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    usuario.setEmpresaPendente(null);

                    usuarioRepository.save(usuario);

                    return ResponseEntity.ok(
                            Map.of(
                                    "mensagem",
                                    "Vínculo recusado"
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PutMapping("/{email}/configuracoes-veiculo")
    public ResponseEntity<?> atualizarConfiguracoesVeiculo(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        return usuarioRepository.findByEmail(email)
                .map(usuario -> {
                    usuario.setVeiculo(
                            body.get("veiculo")
                    );

                    usuario.setCapacidadeCarga(
                            body.get("capacidadeCarga")
                    );

                    usuarioRepository.save(usuario);

                    return ResponseEntity.ok(
                            Map.of(
                                    "mensagem",
                                    "Configurações atualizadas"
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PutMapping("/{email}/perfil")
    public ResponseEntity<?> atualizarPerfil(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        var usuarioOptional =
                usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        String novoNome = body.get("nome");
        String novoEmail = body.get("email");

        if (novoNome == null
                || novoNome.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Nome não pode ficar vazio"
                    )
            );
        }

        if (novoEmail == null
                || novoEmail.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "E-mail não pode ficar vazio"
                    )
            );
        }

        novoNome = novoNome.trim();
        novoEmail = novoEmail.trim();

        if (!email.equalsIgnoreCase(novoEmail)) {
            var usuarioComMesmoEmail =
                    usuarioRepository.findByEmail(
                            novoEmail
                    );

            if (usuarioComMesmoEmail.isPresent()) {
                return ResponseEntity.badRequest().body(
                        Map.of(
                                "mensagem",
                                "E-mail já está sendo utilizado"
                        )
                );
            }
        }

        usuario.setNome(novoNome);
        usuario.setEmail(novoEmail);

        usuarioRepository.save(usuario);

        Map<String, Object> resposta =
                new HashMap<>();

        resposta.put(
                "mensagem",
                "Perfil atualizado com sucesso"
        );
        resposta.put("id", usuario.getId());
        resposta.put("nome", usuario.getNome());
        resposta.put("email", usuario.getEmail());
        resposta.put(
                "foto",
                usuario.getFoto() == null
                        ? ""
                        : usuario.getFoto()
        );

        return ResponseEntity.ok(resposta);
    }

    private boolean senhaValida(
            String senhaSalva,
            String senhaInformada
    ) {
        if (senhaSalva == null || senhaInformada == null) {
            return false;
        }

        if (senhaEstaCriptografada(senhaSalva)) {
            try {
                return passwordEncoder.matches(
                        senhaInformada,
                        senhaSalva
                );
            } catch (Exception e) {
                return false;
            }
        }

        return senhaSalva.equals(senhaInformada);
    }

    private boolean senhaEstaCriptografada(
            String senha
    ) {
        if (senha == null) {
            return false;
        }

        return senha.startsWith("$2a$")
                || senha.startsWith("$2b$")
                || senha.startsWith("$2y$");
    }
}