package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.service.MercadoPagoService;
import com.entregueja.backend.service.PagamentoAssinaturaService;
import org.springframework.http.CacheControl;
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

import java.util.List;
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
        ContaAutenticada conta = obterConta(authentication);

        if (requisicao == null
                || requisicao.plano() == null
                || requisicao.chaveIdempotencia() == null
                || requisicao.chaveIdempotencia().isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Plano e chave de idempotência são obrigatórios."
            );
        }

        try {
            Map<String, Object> resultado;

            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                resultado = pagamentoService.criarCobrancaPix(
                        conta.id(),
                        requisicao.plano(),
                        requisicao.chaveIdempotencia()
                );
            } else {
                resultado = pagamentoService.criarCobrancaPix(
                        conta.tipo(),
                        conta.id(),
                        requisicao.plano(),
                        requisicao.chaveIdempotencia()
                );
            }

            return ResponseEntity.ok(resultado);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, e.getMessage()
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, e.getMessage()
            );
        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Não foi possível processar a cobrança no Mercado Pago."
            );
        }
    }

    @GetMapping("/pix/pendentes")
    public ResponseEntity<List<Map<String, Object>>> listarPixPendentes(
            Authentication authentication
    ) {
        ContaAutenticada conta = obterConta(authentication);

        try {
            List<Map<String, Object>> resultado;

            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                resultado = pagamentoService.listarCobrancasPixPendentes(conta.id());
            } else {
                resultado = pagamentoService.listarCobrancasPixPendentes(
                        conta.tipo(), conta.id()
                );
            }

            return ResponseEntity.ok()
                    .cacheControl(CacheControl.noStore())
                    .body(resultado);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Conta não encontrada ou indisponível para consulta."
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Não foi possível listar as cobranças pendentes com segurança."
            );
        }
    }

    @GetMapping("/pix/{pagamentoId}")
    public ResponseEntity<Map<String, Object>> consultarPix(
            Authentication authentication,
            @PathVariable Long pagamentoId
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (pagamentoId == null || pagamentoId <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Identificador de pagamento inválido."
            );
        }

        try {
            Map<String, Object> resultado;

            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                resultado = pagamentoService.consultarCobrancaPix(
                        conta.id(), pagamentoId
                );
            } else {
                resultado = pagamentoService.consultarCobrancaPix(
                        conta.tipo(), conta.id(), pagamentoId
                );
            }

            return ResponseEntity.ok(resultado);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Pagamento não encontrado."
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, e.getMessage()
            );
        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Não foi possível consultar o pagamento no Mercado Pago."
            );
        }
    }

    private ContaAutenticada obterConta(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação necessária."
            );
        }

        String principal = authentication.getName();

        if (principal == null) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida."
            );
        }

        String[] partes = principal.split(":", -1);

        if (partes.length != 2 || !partes[1].matches("[0-9]+")) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida."
            );
        }

        Assinatura.TipoConta tipo = switch (partes[0]) {
            case "EMPRESA" -> Assinatura.TipoConta.EMPRESA;
            case "ENTREGADOR" -> Assinatura.TipoConta.ENTREGADOR;
            default -> throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "Tipo de conta não autorizado a contratar planos."
            );
        };

        try {
            long id = Long.parseLong(partes[1]);

            if (id <= 0) {
                throw new NumberFormatException("ID inválido");
            }

            return new ContaAutenticada(tipo, id);
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida."
            );
        }
    }

    private record ContaAutenticada(
            Assinatura.TipoConta tipo,
            Long id
    ) {}

    public record CriarPixRequest(
            Assinatura.Plano plano,
            String chaveIdempotencia
    ) {}
}
