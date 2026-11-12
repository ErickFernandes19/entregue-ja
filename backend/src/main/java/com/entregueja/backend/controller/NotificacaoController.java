
package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Notificacao;
import com.entregueja.backend.entity.PreferenciaNotificacao;
import com.entregueja.backend.service.NotificacaoService;
import com.entregueja.backend.service.PreferenciaNotificacaoService;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/notificacoes")
public class NotificacaoController {

    private final NotificacaoService notificacaoService;
    private final PreferenciaNotificacaoService preferenciaNotificacaoService;

    public NotificacaoController(
            NotificacaoService notificacaoService,
            PreferenciaNotificacaoService preferenciaNotificacaoService
    ) {
        this.notificacaoService = notificacaoService;
        this.preferenciaNotificacaoService = preferenciaNotificacaoService;
    }

    private ContaAutenticada obterConta(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação necessária"
            );
        }

        String principal = authentication.getName();

        if (principal == null) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida"
            );
        }

        String[] partes = principal.split(":", -1);

        if (partes.length != 2
                || (!"ENTREGADOR".equals(partes[0])
                && !"EMPRESA".equals(partes[0]))) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida"
            );
        }

        try {
            long id = Long.parseLong(partes[1]);

            if (id <= 0) {
                throw new NumberFormatException("ID inválido");
            }

            return new ContaAutenticada(partes[0], id);
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "Autenticação inválida"
            );
        }
    }

    @GetMapping
    public Page<Notificacao> listar(
            Authentication authentication,
            @RequestParam(defaultValue = "0") int pagina,
            @RequestParam(defaultValue = "20") int tamanho
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (pagina < 0 || tamanho < 1 || tamanho > 50) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Parâmetros de paginação inválidos"
            );
        }

        return notificacaoService.listar(
                conta.tipo(),
                conta.id(),
                pagina,
                tamanho
        );
    }

    @GetMapping("/nao-lidas")
    public Map<String, Long> contarNaoLidas(
            Authentication authentication
    ) {
        ContaAutenticada conta = obterConta(authentication);

        return Map.of(
                "quantidade",
                notificacaoService.contarNaoLidas(
                        conta.tipo(),
                        conta.id()
                )
        );
    }

    @GetMapping("/preferencias")
    public PreferenciaNotificacao buscarPreferencias(
            Authentication authentication
    ) {
        ContaAutenticada conta = obterConta(authentication);

        return preferenciaNotificacaoService.buscar(
                conta.tipo(),
                conta.id()
        );
    }

    @PutMapping("/preferencias")
    public PreferenciaNotificacao atualizarPreferencias(
            Authentication authentication,
            @RequestBody PreferenciaNotificacao dados
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (dados == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Preferências inválidas"
            );
        }

        try {
            return preferenciaNotificacaoService.atualizar(
                    conta.tipo(),
                    conta.id(),
                    dados
            );
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    e.getMessage()
            );
        }
    }

    @PutMapping("/{id}/ler")
    public ResponseEntity<Void> marcarComoLida(
            Authentication authentication,
            @PathVariable Long id
    ) {
        ContaAutenticada conta = obterConta(authentication);

        boolean encontrada = notificacaoService.marcarComoLida(
                id,
                conta.tipo(),
                conta.id()
        );

        return encontrada
                ? ResponseEntity.noContent().build()
                : ResponseEntity.notFound().build();
    }

    @PostMapping("/dispositivos")
    public ResponseEntity<Void> registrarDispositivo(
            Authentication authentication,
            @RequestBody DispositivoRequest request
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (request == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Dados do dispositivo inválidos"
            );
        }

        try {
            notificacaoService.registrarDispositivo(
                    conta.tipo(),
                    conta.id(),
                    request.token(),
                    request.plataforma()
            );

            return ResponseEntity.noContent().build();
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    e.getMessage()
            );
        }
    }

    @DeleteMapping("/dispositivos")
    public ResponseEntity<Void> removerDispositivo(
            Authentication authentication,
            @RequestBody DispositivoRequest request
    ) {
        ContaAutenticada conta = obterConta(authentication);

        if (request == null
                || request.token() == null
                || request.token().isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Token FCM inválido"
            );
        }

        try {
            boolean removido = notificacaoService.removerDispositivo(
                    conta.tipo(),
                    conta.id(),
                    request.token()
            );

            return removido
                    ? ResponseEntity.noContent().build()
                    : ResponseEntity.notFound().build();
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    e.getMessage()
            );
        }
    }

    public record DispositivoRequest(
            String token,
            String plataforma
    ) {}

    private record ContaAutenticada(
            String tipo,
            Long id
    ) {}
}
