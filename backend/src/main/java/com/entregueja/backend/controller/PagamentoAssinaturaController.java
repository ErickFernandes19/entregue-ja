package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.service.MercadoPagoService;
import com.entregueja.backend.service.PagamentoAssinaturaService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/pagamentos/assinaturas")
public class PagamentoAssinaturaController {

    private final PagamentoAssinaturaService pagamentoService;

    public PagamentoAssinaturaController(PagamentoAssinaturaService pagamentoService) {
        this.pagamentoService = pagamentoService;
    }

    @PostMapping("/pix")
    public ResponseEntity<Map<String, Object>> criarPix(
            Authentication authentication,
            @RequestBody(required = false) CriarPixRequest requisicao
    ) {
        Long empresaId = obterEmpresaId(authentication);
        if (requisicao == null || requisicao.plano() == null || requisicao.chaveIdempotencia() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Plano e chave de idempotência são obrigatórios.");
        }
        try {
            return ResponseEntity.ok(pagamentoService.criarCobrancaPix(
                    empresaId, requisicao.plano(), requisicao.chaveIdempotencia()
            ));
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage());
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage());
        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Não foi possível processar a cobrança no Mercado Pago.");
        }
    }

    @GetMapping("/pix/{pagamentoId}")
    public ResponseEntity<Map<String, Object>> consultarPix(
            Authentication authentication,
            @PathVariable Long pagamentoId
    ) {
        Long empresaId = obterEmpresaId(authentication);
        if (pagamentoId == null || pagamentoId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Identificador de pagamento inválido.");
        }
        try {
            return ResponseEntity.ok(pagamentoService.consultarCobrancaPix(empresaId, pagamentoId));
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Pagamento não encontrado.");
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage());
        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Não foi possível consultar o pagamento no Mercado Pago.");
        }
    }

    private Long obterEmpresaId(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação necessária.");
        }
        String principal = authentication.getName();
        if (principal == null || !principal.startsWith("EMPRESA:")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Apenas empresas podem contratar planos.");
        }
        String[] partes = principal.split(":", -1);
        if (partes.length != 2) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida.");
        }
        try {
            long id = Long.parseLong(partes[1]);
            if (id <= 0) {
                throw new NumberFormatException("ID inválido");
            }
            return id;
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida.");
        }
    }

    public record CriarPixRequest(Assinatura.Plano plano, String chaveIdempotencia) {}
}
