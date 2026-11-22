package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.service.AssinaturaRecorrenteService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/pagamentos/assinaturas/recorrentes")
public class AssinaturaRecorrenteController {

    private final AssinaturaRecorrenteService assinaturaRecorrenteService;

    public AssinaturaRecorrenteController(AssinaturaRecorrenteService assinaturaRecorrenteService) {
        this.assinaturaRecorrenteService = assinaturaRecorrenteService;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> criar(
            Authentication authentication,
            @RequestHeader(value = "X-Idempotency-Key", required = false) String chaveIdempotencia,
            @RequestBody CriarAssinaturaRequest pedido
    ) {
        Long empresaId = obterEmpresaId(authentication);
        if (pedido == null || pedido.plano() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Plano obrigatório.");
        }
        if (chaveIdempotencia == null || chaveIdempotencia.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Chave de idempotência obrigatória.");
        }
        try {
            return ResponseEntity.status(HttpStatus.CREATED).body(
                    assinaturaRecorrenteService.criar(empresaId, pedido.plano(), chaveIdempotencia)
            );
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage(), e);
        } catch (IllegalStateException e) {
            e.printStackTrace();
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage(), e);
        }
    }

    @GetMapping
    public List<Map<String, Object>> listar(Authentication authentication) {
        return assinaturaRecorrenteService.listar(obterEmpresaId(authentication));
    }

    @GetMapping("/{assinaturaId}")
    public Map<String, Object> consultar(
            Authentication authentication,
            @PathVariable Long assinaturaId
    ) {
        try {
            return assinaturaRecorrenteService.consultar(obterEmpresaId(authentication), assinaturaId);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage(), e);
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage(), e);
        }
    }

    @PostMapping("/{assinaturaId}/cancelar")
    public Map<String, Object> cancelar(
            Authentication authentication,
            @PathVariable Long assinaturaId
    ) {
        try {
            return assinaturaRecorrenteService.cancelar(obterEmpresaId(authentication), assinaturaId);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage(), e);
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage(), e);
        }
    }

    private Long obterEmpresaId(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação obrigatória.");
        }
        String principal = authentication.getName();
        if (principal == null || !principal.matches("EMPRESA:[0-9]+")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Acesso exclusivo para empresas.");
        }
        try {
            Long id = Long.parseLong(principal.substring("EMPRESA:".length()));
            if (id <= 0) throw new NumberFormatException();
            return id;
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Conta empresarial inválida.");
        }
    }

    public record CriarAssinaturaRequest(Assinatura.Plano plano) {
    }
}
