package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.service.AssinaturaRecorrenteService;
import com.entregueja.backend.service.MercadoPagoService;
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
import java.util.regex.Pattern;

@RestController
@RequestMapping("/pagamentos/assinaturas/recorrentes")
public class AssinaturaRecorrenteController {

    private static final Pattern EMAIL_PATTERN =
            Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

    private final AssinaturaRecorrenteService assinaturaRecorrenteService;

    public AssinaturaRecorrenteController(
            AssinaturaRecorrenteService assinaturaRecorrenteService
    ) {
        this.assinaturaRecorrenteService = assinaturaRecorrenteService;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> criar(
            Authentication authentication,
            @RequestHeader(value = "X-Idempotency-Key", required = false)
            String chaveIdempotencia,
            @RequestBody(required = false) CriarAssinaturaRequest pedido
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (pedido == null || pedido.plano() == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Plano obrigatório."
            );
        }

        if (pedido.plano() == Assinatura.Plano.GRATUITO) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Selecione um plano pago válido."
            );
        }

        if (chaveIdempotencia == null || chaveIdempotencia.isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Chave de idempotência obrigatória."
            );
        }

        String emailPagador = pedido.emailPagador();

        if (emailPagador == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "E-mail do responsável pelo pagamento é obrigatório."
            );
        }

        emailPagador = emailPagador.trim();

        if (emailPagador.isEmpty()
                || emailPagador.length() > 254
                || !EMAIL_PATTERN.matcher(emailPagador).matches()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Informe um e-mail válido para o responsável pelo pagamento."
            );
        }

        try {
            Map<String, Object> resultado;

            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                resultado = assinaturaRecorrenteService.criar(
                        conta.id(),
                        pedido.plano(),
                        chaveIdempotencia,
                        emailPagador
                );
            } else {
                resultado = assinaturaRecorrenteService.criar(
                        conta.tipo(),
                        conta.id(),
                        pedido.plano(),
                        chaveIdempotencia,
                        emailPagador
                );
            }

            return ResponseEntity.status(HttpStatus.CREATED).body(resultado);

        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Não foi possível criar a assinatura no Mercado Pago."
            );
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    e.getMessage()
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    e.getMessage()
            );
        }
    }

    @GetMapping
    public List<Map<String, Object>> listar(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);

        try {
            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                return assinaturaRecorrenteService.listar(conta.id());
            }

            return assinaturaRecorrenteService.listar(
                    conta.tipo(),
                    conta.id()
            );

        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Conta não encontrada."
            );
        }
    }

    @GetMapping("/{assinaturaId}")
    public Map<String, Object> consultar(
            Authentication authentication,
            @PathVariable Long assinaturaId
    ) {
        ContaAutenticada conta = obterConta(authentication);
        validarAssinaturaId(assinaturaId);

        try {
            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                return assinaturaRecorrenteService.consultar(
                        conta.id(),
                        assinaturaId
                );
            }

            return assinaturaRecorrenteService.consultar(
                    conta.tipo(),
                    conta.id(),
                    assinaturaId
            );

        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Não foi possível consultar a assinatura no Mercado Pago."
            );
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Assinatura não encontrada."
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    e.getMessage()
            );
        }
    }

    @PostMapping("/{assinaturaId}/cancelar")
    public Map<String, Object> cancelar(
            Authentication authentication,
            @PathVariable Long assinaturaId
    ) {
        ContaAutenticada conta = obterConta(authentication);
        validarAssinaturaId(assinaturaId);

        try {
            if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
                return assinaturaRecorrenteService.cancelar(
                        conta.id(),
                        assinaturaId
                );
            }

            return assinaturaRecorrenteService.cancelar(
                    conta.tipo(),
                    conta.id(),
                    assinaturaId
            );

        } catch (MercadoPagoService.MercadoPagoException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Não foi possível cancelar a assinatura no Mercado Pago."
            );
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Assinatura não encontrada."
            );
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    e.getMessage()
            );
        }
    }

    private void validarAssinaturaId(Long assinaturaId) {
        if (assinaturaId == null || assinaturaId <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Identificador de assinatura inválido."
            );
        }
    }

    private ContaAutenticada obterConta(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação obrigatória."
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

    public record CriarAssinaturaRequest(
            Assinatura.Plano plano,
            String emailPagador
    ) {}
}