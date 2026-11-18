package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.EntregaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import com.entregueja.backend.service.AssinaturaService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/assinaturas")
public class AssinaturaController {

    private static final ZoneId FUSO = ZoneId.of("America/Sao_Paulo");

    private final AssinaturaService assinaturaService;
    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;
    private final EntregaRepository entregaRepository;

    public AssinaturaController(
            AssinaturaService assinaturaService,
            EmpresaRepository empresaRepository,
            UsuarioRepository usuarioRepository,
            EntregaRepository entregaRepository
    ) {
        this.assinaturaService = assinaturaService;
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
        this.entregaRepository = entregaRepository;
    }

    @GetMapping("/atual")
    public ResponseEntity<Assinatura> buscarAtual(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);
        Assinatura assinatura = assinaturaService.obterOuCriarGratuita(conta.tipo(), conta.id());
        return ResponseEntity.ok(assinatura);
    }

    @GetMapping("/historico")
    public List<Assinatura> listarHistorico(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);
        assinaturaService.obterOuCriarGratuita(conta.tipo(), conta.id());
        return assinaturaService.listarHistorico(conta.tipo(), conta.id());
    }

    @GetMapping("/consumo")
    public ResponseEntity<Map<String, Object>> consultarConsumo(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);
        Assinatura assinatura = assinaturaService.obterOuCriarGratuita(conta.tipo(), conta.id());
        LocalDate hoje = LocalDate.now(FUSO);
        LocalDateTime inicio = hoje.atStartOfDay();
        LocalDateTime fim = hoje.plusDays(1).atStartOfDay();

        int limiteEntregas = limiteDiario(conta.tipo(), assinatura.getPlano());
        long entregasUtilizadas;
        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("tipoConta", conta.tipo().name());
        resultado.put("plano", assinatura.getPlano().name());
        resultado.put("status", assinatura.getStatus().name());
        resultado.put("dataReferencia", hoje.toString());

        if (conta.tipo() == Assinatura.TipoConta.EMPRESA) {
            Empresa empresa = empresaRepository.findById(conta.id())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Empresa não encontrada"));
            entregasUtilizadas = entregaRepository.contarEntregasEmpresaNoPeriodo(empresa, inicio, fim);
            long vinculados = usuarioRepository.countByEmpresa(empresa);
            long pendentes = usuarioRepository.findByEmpresaPendente(empresa).size();
            long ocupadas = vinculados + pendentes;
            int limiteEntregadores = limiteEntregadores(assinatura.getPlano());
            resultado.put("entregadoresVinculados", vinculados);
            resultado.put("solicitacoesPendentes", pendentes);
            resultado.put("vagasOcupadas", ocupadas);
            resultado.put("limiteEntregadores", limiteEntregadores);
            resultado.put("vagasDisponiveis", Math.max(0L, limiteEntregadores - ocupadas));
        } else {
            Usuario entregador = usuarioRepository.findById(conta.id())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Entregador não encontrado"));
            entregasUtilizadas = entregaRepository.contarEntregasAutonomasNoPeriodo(entregador, inicio, fim);
        }

        resultado.put("entregasUtilizadasHoje", entregasUtilizadas);
        resultado.put("limiteEntregasDia", limiteEntregas < 0 ? null : limiteEntregas);
        resultado.put("entregasIlimitadas", limiteEntregas < 0);
        resultado.put("entregasDisponiveisHoje", limiteEntregas < 0 ? null : Math.max(0L, limiteEntregas - entregasUtilizadas));
        return ResponseEntity.ok(resultado);
    }

    private int limiteDiario(Assinatura.TipoConta tipoConta, Assinatura.Plano plano) {
        if (tipoConta == Assinatura.TipoConta.ENTREGADOR && plano == Assinatura.Plano.PROFISSIONAL) {
            return -1;
        }
        return switch (plano) {
            case GRATUITO -> 20;
            case ESSENCIAL -> 50;
            case PROFISSIONAL -> 200;
        };
    }

    private int limiteEntregadores(Assinatura.Plano plano) {
        return switch (plano) {
            case GRATUITO -> 1;
            case ESSENCIAL -> 3;
            case PROFISSIONAL -> 10;
        };
    }

    private ContaAutenticada obterConta(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação necessária");
        }

        String principal = authentication.getName();
        if (principal == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida");
        }

        String[] partes = principal.split(":", -1);
        if (partes.length != 2) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida");
        }

        Assinatura.TipoConta tipo;
        try {
            tipo = Assinatura.TipoConta.valueOf(partes[0]);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida");
        }

        try {
            long id = Long.parseLong(partes[1]);
            if (id <= 0) {
                throw new NumberFormatException("ID inválido");
            }
            return new ContaAutenticada(tipo, id);
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Autenticação inválida");
        }
    }

    private record ContaAutenticada(Assinatura.TipoConta tipo, Long id) {}
}
