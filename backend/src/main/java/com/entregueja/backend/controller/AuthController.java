package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import com.entregueja.backend.service.EmailService;
import com.entregueja.backend.service.CadastroPendenteService;
import com.entregueja.backend.service.JwtService;
import com.entregueja.backend.service.NotificacaoService;
import com.entregueja.backend.service.FirebasePushService;
import com.entregueja.backend.service.AssinaturaService;

import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.time.ZoneId;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Locale;

@RestController
@RequestMapping("/auth")
@CrossOrigin(origins = "*")
public class AuthController {

    private final UsuarioRepository usuarioRepository;
    private final EmpresaRepository empresaRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;
    private final CadastroPendenteService cadastroPendenteService;
    private final JwtService jwtService;
    private final NotificacaoService notificacaoService;
    private final FirebasePushService firebasePushService;
    private final AssinaturaService assinaturaService;
    private final EntityManager entityManager;

    public AuthController(
            UsuarioRepository usuarioRepository,
            EmpresaRepository empresaRepository,
            PasswordEncoder passwordEncoder,
            EmailService emailService,
            CadastroPendenteService cadastroPendenteService,
            JwtService jwtService,
            NotificacaoService notificacaoService,
            FirebasePushService firebasePushService,
            AssinaturaService assinaturaService,
            EntityManager entityManager
    ) {
        this.usuarioRepository = usuarioRepository;
        this.empresaRepository = empresaRepository;
        this.passwordEncoder = passwordEncoder;
        this.emailService = emailService;
        this.cadastroPendenteService = cadastroPendenteService;
        this.jwtService = jwtService;
        this.notificacaoService = notificacaoService;
        this.firebasePushService = firebasePushService;
        this.assinaturaService = assinaturaService;
        this.entityManager = entityManager;
    }

    private Long obterIdAutenticado() {
        Authentication authentication =
                SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }

        String principal = authentication.getName();

        if (principal == null || !principal.startsWith("ENTREGADOR:")) {
            return null;
        }

        try {
            return Long.parseLong(principal.substring("ENTREGADOR:".length()));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private boolean usuarioAutorizado(Usuario usuario) {
        Long idAutenticado = obterIdAutenticado();

        return idAutenticado != null
                && idAutenticado.equals(usuario.getId());
    }

    @PostMapping("/esqueci-senha")
    public ResponseEntity<?> esqueciSenha(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");

        if (email == null || email.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe o e-mail")
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
                new java.security.SecureRandom().nextInt(1000000)
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
                    Map.of("mensagem", "Código expirado")
            );
        }

        if (!usuario.getCodigoRecuperacao()
                .equals(codigo.trim())) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Código inválido")
            );
        }

        return ResponseEntity.ok(
                Map.of("mensagem", "Código válido")
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

        if (!senhaForte(novaSenha)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "A senha deve ter pelo menos 8 caracteres, incluindo letra maiúscula, minúscula, número e caractere especial")
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
                    Map.of("mensagem", "Código expirado")
            );
        }

        if (!usuario.getCodigoRecuperacao()
                .equals(codigo.trim())) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Código inválido")
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

        var usuarioOptional =
                usuarioRepository.findByEmail(email.trim());

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        Usuario usuario = usuarioOptional.get();

        if (!senhaValida(usuario.getSenha(), senha)) {
            return ResponseEntity.status(401).body(
                    Map.of(
                            "mensagem",
                            "E-mail ou senha inválidos"
                    )
            );
        }

        if (!senhaEstaCriptografada(usuario.getSenha())) {
            usuario.setSenha(passwordEncoder.encode(senha));
            usuarioRepository.save(usuario);
        }

        String token = jwtService.gerarToken(
                usuario.getId(),
                "ENTREGADOR"
        );

        Map<String, Object> resposta = new HashMap<>();

        resposta.put(
                "mensagem",
                "Login realizado com sucesso"
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
        resposta.put("token", token);

        return ResponseEntity.ok(resposta);
    }

    @GetMapping("/{email}/perfil")
    public ResponseEntity<?> perfil(
            @PathVariable String email
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

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
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(
            @RequestBody Usuario usuario
    ) {
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

        String email = normalizarEmail(usuario.getEmail());

        if (!emailValido(email)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe um e-mail válido")
            );
        }

        if (usuario.getSenha() == null
                || usuario.getSenha().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Senha é obrigatória")
            );
        }

        if (!senhaForte(usuario.getSenha())) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "A senha deve ter pelo menos 8 caracteres, incluindo letra maiúscula, minúscula, número e caractere especial")
            );
        }

        if (emailJaCadastrado(email)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Este e-mail já está cadastrado")
            );
        }

        try {
            cadastroPendenteService.solicitarCadastro(
                    "ENTREGADOR",
                    usuario.getNome(),
                    email,
                    usuario.getSenha()
            );
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", e.getMessage())
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(
                    Map.of("mensagem", "Não foi possível enviar o código de verificação")
            );
        }

        return ResponseEntity.ok(
                Map.of("mensagem", "Código de verificação enviado para o e-mail")
        );
    }

    @PostMapping("/reenviar-codigo")
    public ResponseEntity<?> reenviarCodigo(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");

        if (email == null || !emailValido(normalizarEmail(email))) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe um e-mail válido")
            );
        }

        String emailNormalizado = normalizarEmail(email);

        if (emailJaCadastrado(emailNormalizado)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Este e-mail já está cadastrado")
            );
        }

        try {
            cadastroPendenteService.reenviarCodigo(
                    "ENTREGADOR", emailNormalizado
            );
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", e.getMessage())
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(
                    Map.of("mensagem", "Não foi possível reenviar o código de verificação")
            );
        }

        return ResponseEntity.ok(
                Map.of("mensagem", "Novo código de verificação enviado para o e-mail")
        );
    }

    @Transactional
    @PostMapping("/confirmar-cadastro")
    public ResponseEntity<?> confirmarCadastro(
            @RequestBody Map<String, String> body
    ) {
        String email = body.get("email");
        String codigo = body.get("codigo");

        if (email == null || email.isBlank()
                || codigo == null || codigo.isBlank()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe o e-mail e o código")
            );
        }

        String emailNormalizado = normalizarEmail(email);

        if (!emailValido(emailNormalizado)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe um e-mail válido")
            );
        }

        if (emailJaCadastrado(emailNormalizado)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Este e-mail já está cadastrado")
            );
        }

        CadastroPendenteService.DadosCadastro dados;

        try {
            dados = cadastroPendenteService.confirmarCodigo(
                    "ENTREGADOR", emailNormalizado, codigo
            );
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", e.getMessage())
            );
        }

        Usuario usuario = new Usuario();
        usuario.setNome(dados.nome());
        usuario.setEmail(dados.email());
        usuario.setSenha(dados.senhaHash());
        usuario.setEmpresa(null);
        usuario.setEmpresaPendente(null);
        usuario.setDataVinculo(null);
        usuario.setFoto(null);
        usuario.setCodigoRecuperacao(null);
        usuario.setCodigoRecuperacaoExpira(null);

        Usuario usuarioSalvo = usuarioRepository.save(usuario);
        assinaturaService.obterOuCriarGratuita(Assinatura.TipoConta.ENTREGADOR, usuarioSalvo.getId());

        return ResponseEntity.ok(
                Map.of("mensagem", "Usuário cadastrado com sucesso")
        );
    }

    @PutMapping("/{email}/foto")
    public ResponseEntity<?> atualizarFotoUsuario(
            @PathVariable String email,
            @RequestParam("foto") MultipartFile foto
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        try {
            if (foto == null || foto.isEmpty()) {
                return ResponseEntity.badRequest().body(
                        Map.of("mensagem", "Selecione uma foto")
                );
            }

            String pasta = "uploads/usuarios/";

            Files.createDirectories(Paths.get(pasta));

            String original = foto.getOriginalFilename();

            if (original == null || original.isBlank()) {
                original = "perfil.jpg";
            }

            original = original.replaceAll("[^a-zA-Z0-9._-]", "_");

            String nomeArquivo =
                    usuario.getId()
                            + "_"
                            + System.currentTimeMillis()
                            + "_"
                            + original;

            Path caminho = Paths.get(pasta, nomeArquivo);

            Files.write(caminho, foto.getBytes());

            String urlFoto = "/uploads/usuarios/" + nomeArquivo;

            usuario.setFoto(urlFoto);
            usuarioRepository.save(usuario);

            return ResponseEntity.ok(
                    Map.of(
                            "mensagem", "Foto atualizada com sucesso",
                            "foto", urlFoto
                    )
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(
                    Map.of("mensagem", "Erro ao salvar foto")
            );
        }
    }

    @GetMapping("/{email}/empresa-vinculada")
    public ResponseEntity<?> empresaVinculada(
            @PathVariable String email
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        if (usuario.getEmpresa() == null) {
            return ResponseEntity.ok(
                    Map.of("vinculado", false)
            );
        }

        return ResponseEntity.ok(
                Map.of(
                        "vinculado", true,
                        "nome", usuario.getEmpresa().getNome(),
                        "email", usuario.getEmpresa().getEmail()
                )
        );
    }

    @GetMapping("/{email}/vinculo-pendente")
    public ResponseEntity<?> vinculoPendente(
            @PathVariable String email
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        if (usuario.getEmpresaPendente() == null) {
            return ResponseEntity.ok(
                    Map.of("possuiVinculo", false)
            );
        }

        return ResponseEntity.ok(
                Map.of(
                        "possuiVinculo", true,
                        "empresa", usuario.getEmpresaPendente().getNome(),
                        "email", usuario.getEmpresaPendente().getEmail()
                )
        );
    }

    private void notificarEmpresaVinculo(
            Long empresaId,
            String tipo,
            String titulo,
            String mensagem
    ) {
        if (empresaId == null) {
            return;
        }

        try {
            notificacaoService.criarNotificacao(
                    "EMPRESA", empresaId, tipo, titulo, mensagem, null
            );
        } catch (Exception e) {
            System.err.println("Falha ao registrar notificação de vínculo: " + e.getMessage());
        }

        try {
            firebasePushService.enviarParaConta(
                    "EMPRESA", empresaId, tipo, titulo, mensagem, null
            );
        } catch (Exception e) {
            System.err.println("Falha ao enviar push de vínculo: " + e.getMessage());
        }
    }

    @Transactional
    @PutMapping("/{email}/aceitar-vinculo")
    public ResponseEntity<?> aceitarVinculo(
            @PathVariable String email
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        if (usuario.getEmpresaPendente() == null) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Nenhuma solicitação pendente")
            );
        }

        Long empresaId = usuario.getEmpresaPendente().getId();
        Empresa empresa = entityManager.find(Empresa.class, empresaId, LockModeType.PESSIMISTIC_WRITE);

        if (empresa == null) {
            return ResponseEntity.status(404).body(
                    Map.of("mensagem", "Empresa não encontrada")
            );
        }

        entityManager.refresh(usuario, LockModeType.PESSIMISTIC_WRITE);

        if (usuario.getEmpresa() != null) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Entregador já possui empresa vinculada")
            );
        }

        if (usuario.getEmpresaPendente() == null
                || !empresaId.equals(usuario.getEmpresaPendente().getId())) {
            return ResponseEntity.status(409).body(
                    Map.of("mensagem", "A solicitação de vínculo não está mais disponível")
            );
        }

        Assinatura assinatura = assinaturaService.obterOuCriarGratuita(
                Assinatura.TipoConta.EMPRESA,
                empresaId
        );

        int limite = switch (assinatura.getPlano()) {
            case GRATUITO -> 1;
            case ESSENCIAL -> 3;
            case PROFISSIONAL -> 10;
        };

        long total = usuarioRepository.countByEmpresa(empresa);

        if (total >= limite) {
            return ResponseEntity.status(409).body(
                    Map.of(
                            "mensagem", "A empresa atingiu o limite de entregadores do plano atual",
                            "limite", limite,
                            "total", total
                    )
            );
        }

        String nomeEntregador = usuario.getNome();
        usuario.setEmpresa(empresa);
        usuario.setEmpresaPendente(null);
        usuario.setDataVinculo(LocalDateTime.now(ZoneId.of("America/Sao_Paulo")));
        usuarioRepository.saveAndFlush(usuario);

        notificarEmpresaVinculo(
                empresaId,
                "VINCULO_ACEITO",
                "Vínculo aceito",
                "O entregador " + nomeEntregador + " aceitou a solicitação de vínculo."
        );

        return ResponseEntity.ok(Map.of("mensagem", "Vínculo aceito"));
    }

    @PutMapping("/{email}/recusar-vinculo")
    public ResponseEntity<?> recusarVinculo(
            @PathVariable String email
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        if (usuario.getEmpresaPendente() == null) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Nenhuma solicitação pendente")
            );
        }

        Long empresaId = usuario.getEmpresaPendente().getId();
        String nomeEntregador = usuario.getNome();

        usuario.setEmpresaPendente(null);
        usuarioRepository.save(usuario);

        notificarEmpresaVinculo(
                empresaId,
                "VINCULO_RECUSADO",
                "Vínculo recusado",
                "O entregador " + nomeEntregador + " recusou a solicitação de vínculo."
        );

        return ResponseEntity.ok(
                Map.of("mensagem", "Vínculo recusado")
        );
    }

    @Transactional
    @PutMapping("/{email}/desvincular")
    public ResponseEntity<?> desvincularEmpresa(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        Long entregadorId = obterIdAutenticado();
        if (entregadorId == null) {
            return ResponseEntity.status(403).body(
                    Map.of("mensagem", "Acesso permitido apenas ao entregador autenticado")
            );
        }

        var usuarioOptional = usuarioRepository.findById(entregadorId);
        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();
        if (!usuario.getEmail().equalsIgnoreCase(email)) {
            return ResponseEntity.status(403).body(
                    Map.of("mensagem", "Você não pode encerrar o vínculo de outro entregador")
            );
        }

        String empresaEmail = body == null ? null : body.get("empresaEmail");
        if (empresaEmail == null || empresaEmail.isBlank()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe a empresa que deseja desvincular")
            );
        }

        if (usuario.getEmpresa() == null) {
            return ResponseEntity.status(409).body(
                    Map.of("mensagem", "Você não possui uma empresa vinculada")
            );
        }

        Long empresaId = usuario.getEmpresa().getId();
        Empresa empresa = entityManager.find(
                Empresa.class, empresaId, LockModeType.PESSIMISTIC_WRITE
        );

        if (empresa == null) {
            return ResponseEntity.status(404).body(
                    Map.of("mensagem", "Empresa não encontrada")
            );
        }

        entityManager.refresh(usuario, LockModeType.PESSIMISTIC_WRITE);

        if (!usuario.getEmail().equalsIgnoreCase(email)) {
            return ResponseEntity.status(403).body(
                    Map.of("mensagem", "Não foi possível confirmar sua conta. Atualize o perfil.")
            );
        }

        if (usuario.getEmpresa() == null
                || !empresaId.equals(usuario.getEmpresa().getId())
                || !empresa.getEmail().equalsIgnoreCase(empresaEmail.trim())) {
            return ResponseEntity.status(409).body(
                    Map.of("mensagem", "Seu vínculo foi alterado. Atualize o perfil e tente novamente.")
            );
        }

        boolean possuiEntregasAtivas = !entityManager.createQuery("""
                SELECT e FROM Entrega e
                WHERE e.empresa.id = :empresaId
                  AND e.entregador.id = :entregadorId
                  AND e.status IN ('PENDENTE', 'EM_ROTA')
                """, Entrega.class)
                .setParameter("empresaId", empresaId)
                .setParameter("entregadorId", entregadorId)
                .setLockMode(LockModeType.PESSIMISTIC_WRITE)
                .setMaxResults(1)
                .getResultList()
                .isEmpty();

        if (possuiEntregasAtivas) {
            return ResponseEntity.status(409).body(
                    Map.of("mensagem", "Você possui entregas pendentes ou em rota desta empresa. Resolva essas entregas antes de encerrar o vínculo.")
            );
        }

        String nomeEntregador = usuario.getNome();
        usuario.setEmpresa(null);
        usuario.setDataVinculo(null);
        usuarioRepository.saveAndFlush(usuario);

        notificarEmpresaVinculo(
                empresaId,
                "VINCULO_ENCERRADO",
                "Vínculo encerrado",
                "O entregador " + nomeEntregador + " encerrou seu vínculo com a empresa."
        );

        return ResponseEntity.ok(Map.of(
                "mensagem", "Vínculo encerrado com sucesso",
                "vinculado", false
        ));
    }

    @PutMapping("/{email}/configuracoes-veiculo")
    public ResponseEntity<?> atualizarConfiguracoesVeiculo(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        usuario.setVeiculo(body.get("veiculo"));
        usuario.setCapacidadeCarga(body.get("capacidadeCarga"));

        usuarioRepository.save(usuario);

        return ResponseEntity.ok(
                Map.of("mensagem", "Configurações atualizadas")
        );
    }

    @PutMapping("/{email}/perfil")
    public ResponseEntity<?> atualizarPerfil(
            @PathVariable String email,
            @RequestBody Map<String, String> body
    ) {
        var usuarioOptional = usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Usuario usuario = usuarioOptional.get();

        if (!usuarioAutorizado(usuario)) {
            return ResponseEntity.status(403).build();
        }

        String novoNome = body.get("nome");
        String novoEmail = body.get("email");

        if (novoNome == null || novoNome.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Nome não pode ficar vazio")
            );
        }

        if (novoEmail == null || novoEmail.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "E-mail não pode ficar vazio")
            );
        }

        novoNome = novoNome.trim();
        novoEmail = normalizarEmail(novoEmail);

        if (!emailValido(novoEmail)) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe um e-mail válido")
            );
        }

        var usuarioComMesmoEmail = usuarioRepository.findByEmail(novoEmail);

        if (empresaRepository.findByEmail(novoEmail).isPresent()
                || (usuarioComMesmoEmail.isPresent()
                && !usuarioComMesmoEmail.get().getId().equals(usuario.getId()))) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Este e-mail já está sendo utilizado")
            );
        }

        usuario.setNome(novoNome);
        usuario.setEmail(novoEmail);

        usuarioRepository.save(usuario);

        Map<String, Object> resposta = new HashMap<>();

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

    private String normalizarEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private boolean emailValido(String email) {
        return email != null
                && email.length() <= 254
                && email.matches("^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)+$");
    }

    private boolean emailJaCadastrado(String email) {
        return usuarioRepository.findByEmail(email).isPresent()
                || empresaRepository.findByEmail(email).isPresent();
    }

    private boolean senhaForte(String senha) {
        return senha != null
                && senha.length() >= 8
                && senha.matches(".*[A-Z].*")
                && senha.matches(".*[a-z].*")
                && senha.matches(".*[0-9].*")
                && senha.matches(".*[^A-Za-z0-9].*");
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
