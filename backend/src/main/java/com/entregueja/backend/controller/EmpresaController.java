
package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import com.entregueja.backend.service.JwtService;
import com.entregueja.backend.service.R2StorageService;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/empresas")
@CrossOrigin(origins = "*")
public class EmpresaController {

    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final R2StorageService r2StorageService;

    public EmpresaController(
            EmpresaRepository empresaRepository,
            UsuarioRepository usuarioRepository,
            PasswordEncoder passwordEncoder,
            JwtService jwtService,
            R2StorageService r2StorageService
    ) {
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.r2StorageService = r2StorageService;
    }

    private Long obterIdAutenticado() {
        Authentication authentication =
                SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }

        String principal = authentication.getName();

        if (principal == null || !principal.startsWith("EMPRESA:")) {
            return null;
        }

        try {
            return Long.parseLong(
                    principal.substring("EMPRESA:".length())
            );
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private boolean empresaAutorizada(Empresa empresa) {
        Long idAutenticado = obterIdAutenticado();

        return idAutenticado != null
                && idAutenticado.equals(empresa.getId());
    }

    private String referenciaFoto(Empresa empresa) {
        String foto = empresa.getFoto();

        if (foto == null || foto.isBlank()) {
            return "";
        }

        if (foto.startsWith("empresas/")) {
            return "/empresas/" + empresa.getId() + "/foto/arquivo";
        }

        return foto;
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(
            @RequestBody Empresa empresa
    ) {
        if (empresa.getNome() == null
                || empresa.getNome().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Nome é obrigatório")
            );
        }

        if (empresa.getEmail() == null
                || empresa.getEmail().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "E-mail é obrigatório")
            );
        }

        if (empresa.getSenha() == null
                || empresa.getSenha().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Senha é obrigatória")
            );
        }

        String email = empresa.getEmail().trim();

        if (empresaRepository.findByEmail(email).isPresent()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "E-mail já cadastrado")
            );
        }

        empresa.setId(null);
        empresa.setNome(empresa.getNome().trim());
        empresa.setEmail(email);
        empresa.setSenha(
                passwordEncoder.encode(empresa.getSenha())
        );
        empresa.setFoto(null);
        empresa.setCodigoRecuperacao(null);
        empresa.setCodigoRecuperacaoExpira(null);

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
                empresaRepository.findByEmail(email.trim());

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        Empresa empresa = empresaOptional.get();

        if (!senhaValida(empresa.getSenha(), senha)) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        if (!senhaEstaCriptografada(empresa.getSenha())) {
            empresa.setSenha(passwordEncoder.encode(senha));
            empresaRepository.save(empresa);
        }

        String token = jwtService.gerarToken(
                empresa.getId(),
                "EMPRESA"
        );

        Map<String, Object> resposta = new HashMap<>();

        resposta.put(
                "mensagem",
                "Login realizado com sucesso"
        );
        resposta.put("id", empresa.getId());
        resposta.put("nome", empresa.getNome());
        resposta.put("email", empresa.getEmail());
        resposta.put("foto", referenciaFoto(empresa));
        resposta.put("token", token);

        return ResponseEntity.ok(resposta);
    }

    @GetMapping("/{email}/entregadores")
    public ResponseEntity<?> listarEntregadores(
            @PathVariable String email
    ) {
        var empresaOptional = empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        var entregadores =
                usuarioRepository.findByEmpresa(empresa)
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

        return ResponseEntity.ok(entregadores);
    }

    @GetMapping("/{email}/entregadores-pendentes")
    public ResponseEntity<?> listarEntregadoresPendentes(
            @PathVariable String email
    ) {
        var empresaOptional = empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        var pendentes =
                usuarioRepository.findByEmpresaPendente(empresa)
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

        return ResponseEntity.ok(pendentes);
    }

    @GetMapping("/{email}/entregadores/total")
    public ResponseEntity<?> totalEntregadores(
            @PathVariable String email
    ) {
        var empresaOptional = empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        return ResponseEntity.ok(
                Map.of(
                        "total",
                        usuarioRepository.countByEmpresa(empresa)
                )
        );
    }

    @PutMapping("/{empresaEmail}/entregadores/{entregadorEmail}/solicitar")
    public ResponseEntity<?> solicitarVinculoEntregador(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(empresaEmail);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(entregadorEmail);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (usuario.getEmpresa() != null) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Entregador já possui empresa vinculada"
                    )
            );
        }

        if (usuario.getEmpresaPendente() != null) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Entregador já possui uma solicitação pendente"
                    )
            );
        }

        usuario.setEmpresaPendente(empresa);

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
        var empresaOptional = empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        if (foto == null || foto.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Selecione uma foto")
            );
        }

        String chaveNova;

        try {
            chaveNova = r2StorageService.enviarImagem(
                    foto,
                    "empresas"
            );
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", e.getMessage())
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(
                    Map.of("mensagem", "Erro ao enviar foto")
            );
        }

        String fotoAnterior = empresa.getFoto();
        String referenciaNova =
                "/empresas/" + empresa.getId() + "/foto/arquivo";

        try {
            empresa.setFoto(chaveNova);
            empresaRepository.save(empresa);
        } catch (Exception e) {
            try {
                r2StorageService.excluirImagem(chaveNova);
            } catch (Exception ignored) {
            }

            return ResponseEntity.internalServerError().body(
                    Map.of("mensagem", "Erro ao atualizar foto")
            );
        }

        if (fotoAnterior != null
                && fotoAnterior.startsWith("empresas/")
                && !fotoAnterior.equals(chaveNova)) {
            try {
                r2StorageService.excluirImagem(fotoAnterior);
            } catch (Exception ignored) {
            }
        }

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Foto atualizada com sucesso",
                        "foto",
                        referenciaNova
                )
        );
    }

    @GetMapping("/{id:\\d+}/foto/arquivo")
    public ResponseEntity<?> buscarFotoEmpresa(
            @PathVariable Long id
    ) {
        var empresaOptional = empresaRepository.findById(id);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        String chave = empresa.getFoto();

        if (chave == null || !chave.startsWith("empresas/")) {
            return ResponseEntity.notFound().build();
        }

        try {
            byte[] imagem = r2StorageService.buscarImagem(chave);

            MediaType tipo = MediaType.IMAGE_JPEG;

            if (chave.endsWith(".png")) {
                tipo = MediaType.IMAGE_PNG;
            } else if (chave.endsWith(".webp")) {
                tipo = MediaType.parseMediaType("image/webp");
            }

            return ResponseEntity.ok()
                    .contentType(tipo)
                    .header("Cache-Control", "private, no-store")
                    .body(imagem);

        } catch (NoSuchKeyException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    @PutMapping("/{empresaEmail}/desvincular/{entregadorEmail}")
    public ResponseEntity<?> desvincularEntregador(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(empresaEmail);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(entregadorEmail);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario entregador = usuarioOptional.get();

        if (entregador.getEmpresa() == null) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Entregador não possui empresa vinculada"
                    )
            );
        }

        if (!entregador.getEmpresa().getId().equals(empresa.getId())) {
            return ResponseEntity.status(403).body(
                    Map.of(
                            "mensagem",
                            "Este entregador não pertence à sua empresa"
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
                empresaRepository.findByEmail(empresaEmail);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        var usuarioOptional =
                usuarioRepository.findByEmail(entregadorEmail);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (usuario.getEmpresaPendente() == null) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Não existe solicitação pendente para este entregador"
                    )
            );
        }

        if (!usuario.getEmpresaPendente()
                .getId()
                .equals(empresa.getId())) {
            return ResponseEntity.badRequest().body(
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
            return ResponseEntity.notFound().build();
        }

        Empresa empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa)) {
            return ResponseEntity.status(403).build();
        }

        String novoNome = body.get("nome");
        String novoEmail = body.get("email");

        if (novoNome == null || novoNome.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Nome não pode ficar vazio"
                    )
            );
        }

        if (novoEmail == null || novoEmail.trim().isEmpty()) {
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
            var empresaComMesmoEmail =
                    empresaRepository.findByEmail(novoEmail);

            if (empresaComMesmoEmail.isPresent()
                    && !empresaComMesmoEmail.get()
                    .getId()
                    .equals(empresa.getId())) {
                return ResponseEntity.badRequest().body(
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

        Map<String, Object> resposta = new HashMap<>();

        resposta.put(
                "mensagem",
                "Perfil da empresa atualizado com sucesso"
        );
        resposta.put("id", empresa.getId());
        resposta.put("nome", empresa.getNome());
        resposta.put("email", empresa.getEmail());
        resposta.put("foto", referenciaFoto(empresa));

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
