package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.EntregaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.util.Map;

@RestController
@RequestMapping("/entregas")
@CrossOrigin(origins = "*")
public class EntregaController {

    private final EntregaRepository entregaRepository;
    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;

    public EntregaController(
            EntregaRepository entregaRepository,
            EmpresaRepository empresaRepository,
            UsuarioRepository usuarioRepository
    ) {
        this.entregaRepository = entregaRepository;
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
    }

    @GetMapping
    public ResponseEntity<?> listarEntregas() {
        return ResponseEntity.ok(
                entregaRepository.findAll()
        );
    }

    @GetMapping("/empresa/{email}")
    public ResponseEntity<?> listarPorEmpresa(
            @PathVariable String email
    ) {
        return empresaRepository.findByEmail(email)
                .map(empresa -> ResponseEntity.ok(
                        entregaRepository.findByEmpresa(empresa)
                ))
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @GetMapping("/empresa/{empresaEmail}/entregador/{entregadorEmail}")
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

        var entregas = entregaRepository
                .findByEmpresa(empresa)
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
        return usuarioRepository.findByEmail(email)
                .map(usuario -> ResponseEntity.ok(
                        entregaRepository.findByEntregador(usuario)
                ))
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @GetMapping("/estatisticas")
    public ResponseEntity<?> estatisticas() {

        long total = entregaRepository.count();

        long entregues =
                entregaRepository.countByEntregue(true);

        long pendentes =
                entregaRepository.countByEntregue(false);

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
        return empresaRepository.findByEmail(email)
                .map(empresa -> {

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
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @GetMapping("/{id}")
    public ResponseEntity<Entrega> buscarPorId(
            @PathVariable Long id
    ) {
        return entregaRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PostMapping("/empresa/{email}/entregador/{entregadorEmail}")
    public ResponseEntity<?> cadastrarEntregaEmpresa(
            @PathVariable String email,
            @PathVariable String entregadorEmail,
            @RequestBody Entrega entrega
    ) {

        var empresaOptional =
                empresaRepository.findByEmail(email);

        var entregadorOptional =
                usuarioRepository.findByEmail(
                        entregadorEmail
                );

        if (
                empresaOptional.isEmpty()
                        || entregadorOptional.isEmpty()
        ) {
            return ResponseEntity.notFound().build();
        }

        entrega.setEmpresa(
                empresaOptional.get()
        );

        entrega.setEntregador(
                entregadorOptional.get()
        );

        entrega.setStatus("PENDENTE");
        entrega.setEntregue(false);

        Entrega entregaSalva =
                entregaRepository.save(entrega);

        return ResponseEntity.ok(
                entregaSalva
        );
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> editarEntrega(
            @PathVariable Long id,
            @RequestBody Entrega dadosAtualizados
    ) {
        return entregaRepository.findById(id)
                .map(entrega -> {

                    entrega.setCliente(
                            dadosAtualizados.getCliente()
                    );

                    entrega.setEndereco(
                            dadosAtualizados.getEndereco()
                    );

                    entrega.setValor(
                            dadosAtualizados.getValor()
                    );

                    entrega.setObservacao(
                            dadosAtualizados.getObservacao()
                    );

                    Entrega entregaSalva =
                            entregaRepository.save(entrega);

                    return ResponseEntity.ok(
                            entregaSalva
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> cancelarEntrega(
            @PathVariable Long id
    ) {

        return entregaRepository.findById(id)
                .map(entrega -> {

                    entrega.setStatus("CANCELADA");
                    entrega.setEntregue(false);

                    entregaRepository.save(entrega);

                    return ResponseEntity.ok(
                            Map.of(
                                    "mensagem",
                                    "Entrega cancelada"
                            )
                    );
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }


    @PutMapping("/{id}/status")
    public ResponseEntity<?> atualizarStatus(
            @PathVariable Long id
    ) {
        return entregaRepository.findById(id)
                .map(entrega -> {

                    entrega.setEntregue(true);
                    entrega.setStatus("ENTREGUE");

                    entrega.setDataFinalizacao(
                            LocalDateTime.now()
                    );

                    entregaRepository.save(entrega);

                    return ResponseEntity.ok().build();
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    @PutMapping("/{id}/em-rota")
    public ResponseEntity<?> marcarEmRota(
            @PathVariable Long id
    ) {
        return entregaRepository.findById(id)
                .map(entrega -> {

                    if (
                            !Boolean.TRUE.equals(
                                    entrega.getEntregue()
                            )
                    ) {
                        entrega.setStatus("EM_ROTA");

                        entregaRepository.save(entrega);
                    }

                    return ResponseEntity.ok().build();
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }


    @PutMapping(
            value = "/{id}/concluir",
            consumes = "multipart/form-data"
    )
    public ResponseEntity<?> concluirEntrega(
            @PathVariable Long id,

            @RequestParam("foto")
            MultipartFile foto,

            @RequestParam("latitude")
            Double latitude,

            @RequestParam("longitude")
            Double longitude,

            @RequestParam(
                    value = "observacao",
                    required = false
            )
            String observacao
    ) {

        return entregaRepository.findById(id)
                .map(entrega -> {

                    try {

                        if (
                                foto == null
                                        || foto.isEmpty()
                        ) {
                            return ResponseEntity
                                    .badRequest()
                                    .body(
                                            Map.of(
                                                    "mensagem",
                                                    "A foto do comprovante é obrigatória"
                                            )
                                    );
                        }

                        String urlFoto =
                                salvarFotoComprovante(
                                        id,
                                        foto
                                );

                        entrega.setFotoComprovante(
                                urlFoto
                        );

                        entrega.setLatitudeComprovante(
                                latitude
                        );

                        entrega.setLongitudeComprovante(
                                longitude
                        );

                        entrega.setDataFinalizacao(
                                LocalDateTime.now()
                        );

                        entrega.setStatus(
                                "ENTREGUE"
                        );

                        entrega.setEntregue(
                                true
                        );

                        entrega.setMotivoNaoEntrega(
                                null
                        );

                        entrega.setJustificativa(
                                observacao
                        );

                        entregaRepository.save(
                                entrega
                        );

                        return ResponseEntity.ok(
                                Map.of(
                                        "mensagem",
                                        "Entrega concluída com sucesso",
                                        "foto",
                                        urlFoto,
                                        "status",
                                        "ENTREGUE"
                                )
                        );

                    } catch (Exception e) {

                        e.printStackTrace();

                        return ResponseEntity
                                .internalServerError()
                                .body(
                                        Map.of(
                                                "mensagem",
                                                "Erro ao registrar comprovante da entrega"
                                        )
                                );
                    }
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }


    @PutMapping(
            value = "/{id}/nao-entregue",
            consumes = "multipart/form-data"
    )
    public ResponseEntity<?> registrarNaoEntrega(
            @PathVariable Long id,

            @RequestParam("foto")
            MultipartFile foto,

            @RequestParam("motivo")
            String motivo,

            @RequestParam("justificativa")
            String justificativa,

            @RequestParam("latitude")
            Double latitude,

            @RequestParam("longitude")
            Double longitude
    ) {

        return entregaRepository.findById(id)
                .map(entrega -> {

                    try {

                        if (
                                foto == null
                                        || foto.isEmpty()
                        ) {
                            return ResponseEntity
                                    .badRequest()
                                    .body(
                                            Map.of(
                                                    "mensagem",
                                                    "A foto da tentativa é obrigatória"
                                            )
                                    );
                        }

                        if (
                                motivo == null
                                        || motivo.trim().isEmpty()
                        ) {
                            return ResponseEntity
                                    .badRequest()
                                    .body(
                                            Map.of(
                                                    "mensagem",
                                                    "Informe o motivo da não entrega"
                                            )
                                    );
                        }

                        if (
                                justificativa == null
                                        || justificativa.trim().isEmpty()
                        ) {
                            return ResponseEntity
                                    .badRequest()
                                    .body(
                                            Map.of(
                                                    "mensagem",
                                                    "Informe uma justificativa"
                                            )
                                    );
                        }

                        String urlFoto =
                                salvarFotoComprovante(
                                        id,
                                        foto
                                );

                        entrega.setFotoComprovante(
                                urlFoto
                        );

                        entrega.setMotivoNaoEntrega(
                                motivo
                        );

                        entrega.setJustificativa(
                                justificativa
                        );

                        entrega.setLatitudeComprovante(
                                latitude
                        );

                        entrega.setLongitudeComprovante(
                                longitude
                        );

                        entrega.setDataFinalizacao(
                                LocalDateTime.now()
                        );

                        entrega.setStatus(
                                "NAO_ENTREGUE"
                        );

                        entrega.setEntregue(
                                false
                        );

                        entregaRepository.save(
                                entrega
                        );

                        return ResponseEntity.ok(
                                Map.of(
                                        "mensagem",
                                        "Tentativa de entrega registrada",
                                        "foto",
                                        urlFoto,
                                        "status",
                                        "NAO_ENTREGUE"
                                )
                        );

                    } catch (Exception e) {

                        e.printStackTrace();

                        return ResponseEntity
                                .internalServerError()
                                .body(
                                        Map.of(
                                                "mensagem",
                                                "Erro ao registrar tentativa de entrega"
                                        )
                                );
                    }
                })
                .orElse(
                        ResponseEntity.notFound().build()
                );
    }

    /*
     * Salva as fotos dos comprovantes.
     */
    private String salvarFotoComprovante(
            Long entregaId,
            MultipartFile foto
    ) throws Exception {

        String pasta =
                "uploads/entregas/";

        Files.createDirectories(
                Paths.get(pasta)
        );

        String original =
                foto.getOriginalFilename();

        if (
                original == null
                        || original.isBlank()
        ) {
            original = "comprovante.jpg";
        }

        /*
         * Evita caracteres estranhos no nome do arquivo.
         */
        original = original.replaceAll(
                "[^a-zA-Z0-9._-]",
                "_"
        );

        String nomeArquivo =
                "entrega_"
                        + entregaId
                        + "_"
                        + System.currentTimeMillis()
                        + "_"
                        + original;

        Path caminho =
                Paths.get(
                        pasta,
                        nomeArquivo
                );

        Files.write(
                caminho,
                foto.getBytes()
        );

        return "/uploads/entregas/"
                + nomeArquivo;
    }
}