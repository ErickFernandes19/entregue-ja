package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.EntregaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import com.entregueja.backend.service.R2StorageService;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.time.LocalDateTime;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/entregas")
@CrossOrigin(origins = "*")
public class EntregaController {

    private static final long TAMANHO_MAXIMO_FOTO =
            10 * 1024 * 1024;

    private static final Set<String> TIPOS_FOTO_PERMITIDOS =
            Set.of(
                    "image/jpeg",
                    "image/png",
                    "image/webp"
            );

    private final EntregaRepository entregaRepository;
    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;
    private final R2StorageService r2StorageService;

    public EntregaController(
            EntregaRepository entregaRepository,
            EmpresaRepository empresaRepository,
            UsuarioRepository usuarioRepository,
            R2StorageService r2StorageService
    ) {
        this.entregaRepository = entregaRepository;
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
        this.r2StorageService = r2StorageService;
    }

    private Long obterIdAutenticado(String tipoEsperado) {
        Authentication authentication =
                SecurityContextHolder.getContext()
                        .getAuthentication();

        if (authentication == null
                || !authentication.isAuthenticated()) {
            return null;
        }

        String principal = authentication.getName();

        if (principal == null
                || !principal.startsWith(tipoEsperado + ":")) {
            return null;
        }

        try {
            return Long.parseLong(
                    principal.substring(
                            tipoEsperado.length() + 1
                    )
            );
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private boolean empresaAutorizada(Long empresaId) {
        Long idAutenticado = obterIdAutenticado("EMPRESA");

        return idAutenticado != null
                && idAutenticado.equals(empresaId);
    }

    private boolean entregadorAutorizado(Long entregadorId) {
        Long idAutenticado =
                obterIdAutenticado("ENTREGADOR");

        return idAutenticado != null
                && idAutenticado.equals(entregadorId);
    }

    private boolean podeVisualizar(Entrega entrega) {
        if (entrega.getEmpresa() != null
                && empresaAutorizada(
                entrega.getEmpresa().getId()
        )) {
            return true;
        }

        return entrega.getEntregador() != null
                && entregadorAutorizado(
                entrega.getEntregador().getId()
        );
    }

    private boolean podeGerenciar(Entrega entrega) {
        if (entrega.getEmpresa() != null) {
            return empresaAutorizada(entrega.getEmpresa().getId());
        }

        return entrega.getEntregador() != null
                && entregadorAutorizado(entrega.getEntregador().getId());
    }

    private boolean podeAtualizarStatus(Entrega entrega) {
        return entrega.getEntregador() != null
                && entregadorAutorizado(
                entrega.getEntregador().getId()
        );
    }

    private boolean entregaFinalizadaOuCancelada(
            Entrega entrega
    ) {
        return "CANCELADA".equals(entrega.getStatus())
                || "ENTREGUE".equals(entrega.getStatus())
                || "NAO_ENTREGUE".equals(entrega.getStatus());
    }

    private boolean fotoValida(MultipartFile foto) {
        if (foto == null || foto.isEmpty()) {
            return false;
        }

        if (foto.getSize() > TAMANHO_MAXIMO_FOTO) {
            return false;
        }

        String tipo = foto.getContentType();

        return tipo != null
                && TIPOS_FOTO_PERMITIDOS.contains(
                tipo.toLowerCase(Locale.ROOT)
        );
    }

    private boolean coordenadasValidas(
            Double latitude,
            Double longitude
    ) {
        return latitude != null
                && longitude != null
                && Double.isFinite(latitude)
                && Double.isFinite(longitude)
                && latitude >= -90
                && latitude <= 90
                && longitude >= -180
                && longitude <= 180;
    }

    private String referenciaComprovante(Entrega entrega) {
        String foto = entrega.getFotoComprovante();

        if (foto == null || foto.isBlank()) {
            return "";
        }

        if (foto.startsWith("entregas/")) {
            return "/entregas/"
                    + entrega.getId()
                    + "/comprovante/arquivo";
        }

        return foto;
    }

    private void excluirFotoNovaSeNecessario(String chave) {
        if (chave == null || chave.isBlank()) {
            return;
        }

        try {
            r2StorageService.excluirImagem(chave);
        } catch (Exception e) {
            System.err.println(
                    "Não foi possível excluir a imagem do R2: "
                            + e.getMessage()
            );
        }
    }

    @GetMapping
    public ResponseEntity<?> listarEntregas() {
        Long empresaId = obterIdAutenticado("EMPRESA");
        Long entregadorId =
                obterIdAutenticado("ENTREGADOR");

        if (empresaId == null && entregadorId == null) {
            return ResponseEntity.status(403).build();
        }

        var entregas = entregaRepository.findAll()
                .stream()
                .filter(this::podeVisualizar)
                .toList();

        return ResponseEntity.ok(entregas);
    }

    @GetMapping("/empresa/{email}")
    public ResponseEntity<?> listarPorEmpresa(
            @PathVariable String email
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa.getId())) {
            return ResponseEntity.status(403).build();
        }

        return ResponseEntity.ok(
                entregaRepository.findByEmpresa(empresa)
        );
    }

    @GetMapping(
            "/empresa/{empresaEmail}/entregador/{entregadorEmail}"
    )
    public ResponseEntity<?> listarPorEmpresaEEntregador(
            @PathVariable String empresaEmail,
            @PathVariable String entregadorEmail
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(empresaEmail);

        var entregadorOptional =
                usuarioRepository.findByEmail(entregadorEmail);

        if (empresaOptional.isEmpty()
                || entregadorOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var empresa = empresaOptional.get();
        var entregador = entregadorOptional.get();

        if (!empresaAutorizada(empresa.getId())) {
            return ResponseEntity.status(403).build();
        }

        var entregas = entregaRepository.findByEmpresa(empresa)
                .stream()
                .filter(entrega ->
                        entrega.getEntregador() != null
                                && entrega.getEntregador()
                                .getId()
                                .equals(entregador.getId())
                )
                .toList();

        return ResponseEntity.ok(entregas);
    }

    @GetMapping("/entregador/{email}")
    public ResponseEntity<?> entregasDoEntregador(
            @PathVariable String email
    ) {
        var usuarioOptional =
                usuarioRepository.findByEmail(email);

        if (usuarioOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var usuario = usuarioOptional.get();

        if (!entregadorAutorizado(usuario.getId())) {
            return ResponseEntity.status(403).build();
        }

        return ResponseEntity.ok(
                entregaRepository.findByEntregador(usuario)
        );
    }

    @GetMapping("/estatisticas")
    public ResponseEntity<?> estatisticas() {
        if (obterIdAutenticado("EMPRESA") == null
                && obterIdAutenticado("ENTREGADOR") == null) {
            return ResponseEntity.status(403).build();
        }

        var entregas = entregaRepository.findAll()
                .stream()
                .filter(this::podeVisualizar)
                .toList();

        long total = entregas.size();

        long entregues = entregas.stream()
                .filter(entrega ->
                        Boolean.TRUE.equals(
                                entrega.getEntregue()
                        )
                )
                .count();

        long pendentes = entregas.stream()
                .filter(entrega ->
                        !Boolean.TRUE.equals(
                                entrega.getEntregue()
                        )
                )
                .count();

        return ResponseEntity.ok(
                Map.of(
                        "total", total,
                        "entregues", entregues,
                        "pendentes", pendentes
                )
        );
    }

    @GetMapping("/estatisticas/empresa/{email}")
    public ResponseEntity<?> estatisticasPorEmpresa(
            @PathVariable String email
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa.getId())) {
            return ResponseEntity.status(403).build();
        }

        long total =
                entregaRepository.countByEmpresaAndStatusNot(
                        empresa,
                        "CANCELADA"
                );

        long entregues =
                entregaRepository.countByEmpresaAndStatus(
                        empresa,
                        "ENTREGUE"
                );

        long pendentes =
                entregaRepository.countByEmpresaAndStatus(
                        empresa,
                        "PENDENTE"
                );

        long emRota =
                entregaRepository.countByEmpresaAndStatus(
                        empresa,
                        "EM_ROTA"
                );

        long naoEntregues =
                entregaRepository.countByEmpresaAndStatus(
                        empresa,
                        "NAO_ENTREGUE"
                );

        return ResponseEntity.ok(
                Map.of(
                        "total", total,
                        "entregues", entregues,
                        "pendentes", pendentes,
                        "emRota", emRota,
                        "naoEntregues", naoEntregues
                )
        );
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> buscarPorId(
            @PathVariable Long id
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeVisualizar(entrega)) {
            return ResponseEntity.status(403).build();
        }

        return ResponseEntity.ok(entrega);
    }

    @GetMapping("/{id}/comprovante/arquivo")
    public ResponseEntity<?> buscarComprovante(
            @PathVariable Long id
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Entrega entrega = entregaOptional.get();

        if (!podeVisualizar(entrega)) {
            return ResponseEntity.status(403).build();
        }

        String chave = entrega.getFotoComprovante();

        if (chave == null
                || !chave.startsWith("entregas/")) {
            return ResponseEntity.notFound().build();
        }

        try {
            byte[] imagem =
                    r2StorageService.buscarImagem(chave);

            MediaType tipo = MediaType.IMAGE_JPEG;

            if (chave.endsWith(".png")) {
                tipo = MediaType.IMAGE_PNG;
            } else if (chave.endsWith(".webp")) {
                tipo = MediaType.parseMediaType(
                        "image/webp"
                );
            }

            return ResponseEntity.ok()
                    .contentType(tipo)
                    .header(
                            "Cache-Control",
                            "private, no-store"
                    )
                    .body(imagem);

        } catch (NoSuchKeyException e) {
            return ResponseEntity.notFound().build();

        } catch (Exception e) {
            e.printStackTrace();

            return ResponseEntity.internalServerError()
                    .build();
        }
    }

    @PostMapping(
            "/empresa/{email}/entregador/{entregadorEmail}"
    )
    public ResponseEntity<?> cadastrarEntregaEmpresa(
            @PathVariable String email,
            @PathVariable String entregadorEmail,
            @RequestBody Entrega entrega
    ) {
        var empresaOptional =
                empresaRepository.findByEmail(email);

        if (empresaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var empresa = empresaOptional.get();

        if (!empresaAutorizada(empresa.getId())) {
            return ResponseEntity.status(403).build();
        }

        var entregadorOptional =
                usuarioRepository.findByEmail(
                        entregadorEmail
                );

        if (entregadorOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entregador = entregadorOptional.get();

        if (entregador.getEmpresa() == null
                || !empresa.getId().equals(
                entregador.getEmpresa().getId()
        )) {
            return ResponseEntity.status(403).body(
                    Map.of(
                            "mensagem",
                            "O entregador não está vinculado à sua empresa"
                    )
            );
        }

        entrega.setId(null);
        entrega.setEmpresa(empresa);
        entrega.setEntregador(entregador);
        entrega.setStatus("PENDENTE");
        entrega.setEntregue(false);

        entrega.setFotoComprovante(null);
        entrega.setMotivoNaoEntrega(null);
        entrega.setJustificativa(null);
        entrega.setDataFinalizacao(null);
        entrega.setLatitudeComprovante(null);
        entrega.setLongitudeComprovante(null);

        Entrega entregaSalva =
                entregaRepository.save(entrega);

        return ResponseEntity.ok(entregaSalva);
    }

    @PostMapping("/entregador")
    public ResponseEntity<?> cadastrarEntregaEntregador(
            @RequestBody Entrega dados
    ) {
        Long entregadorId = obterIdAutenticado("ENTREGADOR");

        if (entregadorId == null) {
            return ResponseEntity.status(403).body(
                    Map.of("mensagem", "Acesso permitido apenas a entregadores")
            );
        }

        var entregadorOptional = usuarioRepository.findById(entregadorId);

        if (entregadorOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        if (dados.getCliente() == null
                || dados.getCliente().isBlank()
                || dados.getEndereco() == null
                || dados.getEndereco().isBlank()) {
            return ResponseEntity.badRequest().body(
                    Map.of("mensagem", "Informe o cliente e o endereço")
            );
        }

        Entrega entrega = new Entrega();
        entrega.setCliente(dados.getCliente().trim());
        entrega.setEndereco(dados.getEndereco().trim());
        entrega.setComplemento(dados.getComplemento());
        entrega.setValor(dados.getValor());
        entrega.setObservacao(dados.getObservacao());
        entrega.setLatitude(dados.getLatitude());
        entrega.setLongitude(dados.getLongitude());
        entrega.setEmpresa(null);
        entrega.setEntregador(entregadorOptional.get());
        entrega.setStatus("PENDENTE");
        entrega.setEntregue(false);

        Entrega entregaSalva = entregaRepository.save(entrega);

        return ResponseEntity.status(201).body(entregaSalva);
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> editarEntrega(
            @PathVariable Long id,
            @RequestBody Entrega dadosAtualizados
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeGerenciar(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Não é possível editar uma entrega finalizada ou cancelada"
                    )
            );
        }

        entrega.setCliente(
                dadosAtualizados.getCliente()
        );
        entrega.setEndereco(
                dadosAtualizados.getEndereco()
        );
        entrega.setComplemento(
                dadosAtualizados.getComplemento()
        );
        entrega.setValor(
                dadosAtualizados.getValor()
        );
        entrega.setObservacao(
                dadosAtualizados.getObservacao()
        );

        Entrega entregaSalva =
                entregaRepository.save(entrega);

        return ResponseEntity.ok(entregaSalva);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> cancelarEntrega(
            @PathVariable Long id
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeGerenciar(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Não é possível cancelar uma entrega finalizada ou já cancelada"
                    )
            );
        }

        entrega.setStatus("CANCELADA");
        entrega.setEntregue(false);

        entregaRepository.save(entrega);

        return ResponseEntity.ok(
                Map.of(
                        "mensagem",
                        "Entrega cancelada"
                )
        );
    }

    @PutMapping("/{id}/status")
    public ResponseEntity<?> atualizarStatus(
            @PathVariable Long id
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeAtualizarStatus(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().build();
        }

        entrega.setEntregue(true);
        entrega.setStatus("ENTREGUE");
        entrega.setDataFinalizacao(LocalDateTime.now());

        entregaRepository.save(entrega);

        return ResponseEntity.ok().build();
    }

    @PutMapping("/{id}/em-rota")
    public ResponseEntity<?> marcarEmRota(
            @PathVariable Long id
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeAtualizarStatus(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().build();
        }

        entrega.setStatus("EM_ROTA");

        entregaRepository.save(entrega);

        return ResponseEntity.ok().build();
    }

    @PutMapping(
            value = "/{id}/concluir",
            consumes = "multipart/form-data"
    )
    public ResponseEntity<?> concluirEntrega(
            @PathVariable Long id,
            @RequestParam("foto") MultipartFile foto,
            @RequestParam("latitude") Double latitude,
            @RequestParam("longitude") Double longitude,
            @RequestParam(
                    value = "observacao",
                    required = false
            ) String observacao
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeAtualizarStatus(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().build();
        }
        System.out.println("=== DEBUG FOTO COMPROVANTE ===");
        System.out.println("Nome: " + foto.getOriginalFilename());
        System.out.println("Tipo MIME: " + foto.getContentType());
        System.out.println("Tamanho: " + foto.getSize());
        System.out.println("Vazia: " + foto.isEmpty());
        if (!fotoValida(foto)) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Envie uma foto JPG, PNG ou WEBP de até 10 MB"
                    )
            );
        }

        if (!coordenadasValidas(
                latitude,
                longitude
        )) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Coordenadas inválidas"
                    )
            );
        }

        String chaveNova = null;

        try {
            chaveNova = r2StorageService.enviarImagem(
                    foto,
                    "entregas"
            );

            entrega.setFotoComprovante(chaveNova);
            entrega.setLatitudeComprovante(latitude);
            entrega.setLongitudeComprovante(longitude);
            entrega.setDataFinalizacao(
                    LocalDateTime.now()
            );
            entrega.setStatus("ENTREGUE");
            entrega.setEntregue(true);
            entrega.setMotivoNaoEntrega(null);
            entrega.setJustificativa(observacao);

            entregaRepository.save(entrega);

            return ResponseEntity.ok(
                    Map.of(
                            "mensagem",
                            "Entrega concluída com sucesso",
                            "foto",
                            referenciaComprovante(entrega),
                            "status",
                            "ENTREGUE"
                    )
            );

        } catch (Exception e) {
            excluirFotoNovaSeNecessario(chaveNova);

            e.printStackTrace();

            return ResponseEntity.internalServerError()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Erro ao registrar comprovante da entrega"
                            )
                    );
        }
    }

    @PutMapping(
            value = "/{id}/nao-entregue",
            consumes = "multipart/form-data"
    )
    public ResponseEntity<?> registrarNaoEntrega(
            @PathVariable Long id,
            @RequestParam("foto") MultipartFile foto,
            @RequestParam("motivo") String motivo,
            @RequestParam("justificativa") String justificativa,
            @RequestParam("latitude") Double latitude,
            @RequestParam("longitude") Double longitude
    ) {
        var entregaOptional =
                entregaRepository.findById(id);

        if (entregaOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entrega = entregaOptional.get();

        if (!podeAtualizarStatus(entrega)) {
            return ResponseEntity.status(403).build();
        }

        if (entregaFinalizadaOuCancelada(entrega)) {
            return ResponseEntity.badRequest().build();
        }

        if (!fotoValida(foto)) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Envie uma foto JPG, PNG ou WEBP de até 10 MB"
                    )
            );
        }

        if (motivo == null
                || motivo.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Informe o motivo da não entrega"
                    )
            );
        }

        if (justificativa == null
                || justificativa.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Informe uma justificativa"
                    )
            );
        }

        if (!coordenadasValidas(
                latitude,
                longitude
        )) {
            return ResponseEntity.badRequest().body(
                    Map.of(
                            "mensagem",
                            "Coordenadas inválidas"
                    )
            );
        }

        String chaveNova = null;

        try {
            chaveNova = r2StorageService.enviarImagem(
                    foto,
                    "entregas"
            );

            entrega.setFotoComprovante(chaveNova);
            entrega.setMotivoNaoEntrega(motivo.trim());
            entrega.setJustificativa(
                    justificativa.trim()
            );
            entrega.setLatitudeComprovante(latitude);
            entrega.setLongitudeComprovante(longitude);
            entrega.setDataFinalizacao(
                    LocalDateTime.now()
            );
            entrega.setStatus("NAO_ENTREGUE");
            entrega.setEntregue(false);

            entregaRepository.save(entrega);

            return ResponseEntity.ok(
                    Map.of(
                            "mensagem",
                            "Tentativa de entrega registrada",
                            "foto",
                            referenciaComprovante(entrega),
                            "status",
                            "NAO_ENTREGUE"
                    )
            );

        } catch (Exception e) {
            excluirFotoNovaSeNecessario(chaveNova);

            e.printStackTrace();

            return ResponseEntity.internalServerError()
                    .body(
                            Map.of(
                                    "mensagem",
                                    "Erro ao registrar tentativa de entrega"
                            )
                    );
        }
    }
}
