package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/empresas")
@CrossOrigin(origins = "*")
public class EmpresaController {

    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;

    public EmpresaController(
            EmpresaRepository empresaRepository,
            UsuarioRepository usuarioRepository,
            PasswordEncoder passwordEncoder
    ) {
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(
            @RequestBody Empresa empresa
    ) {
        if (empresa.getNome() == null
                || empresa.getNome().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Nome é obrigatório"
                    )
            );
        }

        if (empresa.getEmail() == null
                || empresa.getEmail().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "E-mail é obrigatório"
                    )
            );
        }

        if (empresa.getSenha() == null
                || empresa.getSenha().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Senha é obrigatória"
                    )
            );
        }

        String email = empresa.getEmail().trim();

        if (empresaRepository
                .findByEmail(email)
                .isPresent()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "E-mail já cadastrado"
                    )
            );
        }

        empresa.setNome(
                empresa.getNome().trim()
        );

        empresa.setEmail(email);

        empresa.setSenha(
                passwordEncoder.encode(
                        empresa.getSenha()
                )
        );

        empresaRepository.save(empresa);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Empresa cadastrada com sucesso"
                )
        );
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");
        String senha = body.get("senha");

        if (email == null
                || email.trim().isEmpty()
                || senha == null
                || senha.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Informe e-mail e senha"
                    )
            );
        }

        var empresaOptional =
                empresaRepository.findByEmail(
                        email.trim()
                );

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        Empresa empresa = empresaOptional.get();

        if (!senhaValida(
                empresa.getSenha(),
                senha
        )) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        if (!senhaEstaCriptografada(
                empresa.getSenha()
        )) {
            empresa.setSenha(
                    passwordEncoder.encode(senha)
            );

            empresaRepository.save(empresa);
        }

        Map<String, Object> resposta =
                new HashMap<>();

        resposta.put(
                "mensagem",
                "Login realizado com sucesso"
        );
        resposta.put("id", empresa.getId());
        resposta.put("nome", empresa.getNome());
        resposta.put("email", empresa.getEmail());
        resposta.put(
                "foto",
                empresa.getFoto() == null
                        ? ""
                        : empresa.getFoto()
        );

        return ResponseEntity.ok(resposta);
    }

    @GetMapping("/{email}/entregadores")
    public ResponseEntity<?> listarEntregadores(
            @PathVariable String email
    ) {
        return empresaRepository.findByEmail(email)
                .map(empresa -> {

                    var entregadores =
                            usuarioRepository
                                    .findByEmpresa(empresa)
                                    .stream()
                                    .map(usuario -> Map.of(
                                            "id",
                                            usuario.getId(),
                                            "nome",
                                            usuario.getNome(),
                                            "email",
                                            usuario.getEmail(),
                                            "veiculo",
                                            usuario.getVeiculo() == null
                                                    ? ""
                                                    : usuario.getVeiculo(),
                                            "capacidadeCarga",
                                            usuario.getCapacidadeCarga() == null
                                                    ? ""
                                                    : usuario.getCapacidadeCarga(),
                                            "dataVinculo",
                                            usuario.getDataVinculo() == null
                                                    ? ""
                                                    : usuario.getDataVinculo()
                                    ))
                                    .toList();

                    return ResponseEntity.ok(
                            entregadores
                    );
                })
                .orElse(
                        ResponseEntity
                                .notFound()
                                .build()
                );
    }

    @GetMapping("/{email}/entregadores-pendentes")
    public ResponseEntity<?> listarEntregadoresPendentes(
            @PathVariable String email
    ) {
        return empresaRepository.findByEmail(email)
                .map(empresa -> {

                    var pendentes =
                            usuarioRepository
                                    .findByEmpresaPendente(
                                            empresa
                                    )
                                    .stream()
                                    .map(usuario -> Map.of(
                                            "id",
                                            usuario.getId(),
                                            "nome",
                                            usuario.getNome(),
                                            "email",
                                            usuario.getEmail()
                                    ))
                                    .toList();

                    return ResponseEntity.ok(
                            pendentes
                    );
                })
                .orElse(
                        ResponseEntity
                                .notFound()
                                .build()
                );
    }

    @GetMapping("/{email}/entregadores/total")
    public ResponseEntity<?> totalEntregadores(
            @PathVariable String email
    ) {
        return empresaRepository.findByEmail(email)
                .map(empresa ->
                        ResponseEntity.ok(
                                Map.of(
                                        "total",
                                        usuarioRepository
                                                .countByEmpresa(
                                                        empresa
                                                )
                                )
                        )
                )
                .orElse(
                        ResponseEntity
                                .notFound()
                                .build()
                );
    }

    @PutMapping("/{empresaEmail}/entregadores/{entregadorEmail}/solicitar")
    public ResponseEntity<?> solicitarVinculoEntregador(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(
                        empresaEmail
                );

        var usuarioOptional =
                usuarioRepository.findByEmail(
                        entregadorEmail
                );

        if (empresaOptional.isEmpty()
                || usuarioOptional.isEmpty()) {
            return ResponseEntity
                    .notFound()
                    .build();
        }

        Usuario usuario =
                usuarioOptional.get();

        if (usuario.getEmpresa() != null) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Entregador já possui empresa vinculada"
                            )
                    );
        }

        if (usuario.getEmpresaPendente() != null) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Entregador já possui uma solicitação pendente"
                            )
                    );
        }

        usuario.setEmpresaPendente(
                empresaOptional.get()
        );

        usuarioRepository.save(usuario);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Solicitação enviada ao entregador"
                )
        );
    }

    @PutMapping("/{email}/foto")
    public ResponseEntity<?> atualizarFotoEmpresa(
            @PathVariable String email,
            @RequestParam("foto") MultipartFile foto
    ) {
        return empresaRepository.findByEmail(email)
                .map(empresa -> {
                    try {
                        String pasta =
                                "uploads/empresas/";

                        Files.createDirectories(
                                Paths.get(pasta)
                        );

                        String nomeArquivo =
                                email
                                        .replace("@", "_")
                                        .replace(".", "_")
                                        + "_"
                                        + System.currentTimeMillis()
                                        + "_"
                                        + foto.getOriginalFilename();

                        Path caminho =
                                Paths.get(
                                        pasta + nomeArquivo
                                );

                        Files.write(
                                caminho,
                                foto.getBytes()
                        );

                        String urlFoto =
                                "/uploads/empresas/"
                                        + nomeArquivo;

                        empresa.setFoto(urlFoto);

                        empresaRepository.save(
                                empresa
                        );

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
                        ResponseEntity
                                .notFound()
                                .build()
                );
    }

    @PutMapping("/{empresaEmail}/desvincular/{entregadorEmail}")
    public ResponseEntity<?> desvincularEntregador(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresa =
                empresaRepository.findByEmail(
                        empresaEmail
                );

        var usuario =
                usuarioRepository.findByEmail(
                        entregadorEmail
                );

        if (empresa.isEmpty()
                || usuario.isEmpty()) {
            return ResponseEntity
                    .notFound()
                    .build();
        }

        Usuario entregador =
                usuario.get();

        if (entregador.getEmpresa() == null) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Entregador não possui empresa vinculada"
                            )
                    );
        }

        entregador.setEmpresa(null);
        entregador.setDataVinculo(null);

        usuarioRepository.save(entregador);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Entregador desvinculado com sucesso"
                )
        );
    }

    @PutMapping("/{empresaEmail}/entregadores/{entregadorEmail}/cancelar-solicitacao")
    public ResponseEntity<?> cancelarSolicitacaoVinculo(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(
                        empresaEmail
                );

        var usuarioOptional =
                usuarioRepository.findByEmail(
                        entregadorEmail
                );

        if (empresaOptional.isEmpty()
                || usuarioOptional.isEmpty()) {
            return ResponseEntity
                    .notFound()
                    .build();
        }

        Usuario usuario =
                usuarioOptional.get();

        if (usuario.getEmpresaPendente() == null) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Não existe solicitação pendente para este entregador"
                            )
                    );
        }

        if (!usuario
                .getEmpresaPendente()
                .getId()
                .equals(
                        empresaOptional
                                .get()
                                .getId()
                )) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Esta solicitação pertence a outra empresa"
                            )
                    );
        }

        usuario.setEmpresaPendente(null);

        usuarioRepository.save(usuario);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Solicitação cancelada com sucesso"
                )
        );
    }

    @PutMapping("/{email}/perfil")
    public ResponseEntity<?> atualizarPerfilEmpresa(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity
                    .notFound()
                    .build();
        }

        Empresa empresa =
                empresaOptional.get();

        String novoNome = body.get("nome");
        String novoEmail = body.get("email");

        if (novoNome == null
                || novoNome.trim().isEmpty()) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Nome não pode ficar vazio"
                            )
                    );
        }

        if (novoEmail == null
                || novoEmail.trim().isEmpty()) {
            return ResponseEntity
                    .badRequest()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "E-mail não pode ficar vazio"
                            )
                    );
        }

        novoNome = novoNome.trim();
        novoEmail = novoEmail.trim();

        if (!email.equalsIgnoreCase(novoEmail)) {
            var empresaComMesmoEmail =
                    empresaRepository
                            .findByEmail(novoEmail);

            if (empresaComMesmoEmail.isPresent()) {
                return ResponseEntity
                        .badRequest()
                        .body(
                                Map.of(
                                        "mensagem",
                                        "E-mail já está sendo utilizado"
                                )
                        );
            }
        }

        empresa.setNome(novoNome);
        empresa.setEmail(novoEmail);

        empresaRepository.save(empresa);

        Map<String, Object> resposta =
                new HashMap<>();

        resposta.put(
                "mensagem",
                "Perfil da empresa atualizado com sucesso"
        );
        resposta.put("id", empresa.getId());
        resposta.put("nome", empresa.getNome());
        resposta.put("email", empresa.getEmail());
        resposta.put(
                "foto",
                empresa.getFoto() == null
                        ? ""
                        : empresa.getFoto()
        );

        return ResponseEntity.ok(resposta);
    }

    private boolean senhaValida(
            String senhaSalva,
            String senhaInformada
    ) {
        if (senhaSalva == null
                || senhaInformada == null) {
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

        return senhaSalva.equals(
                senhaInformada
        );
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