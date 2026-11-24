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
import org.springframework.web.bind.annotation.PostMapping;
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

    @PostMapping("/teste-essencial")
    public ResponseEntity<Assinatura> iniciarTesteEssencial(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);

        if (conta.tipo() != Assinatura.TipoConta.EMPRESA) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "O teste gratuito está disponível apenas para empresas."
            );
        }

        try {
            Assinatura assinatura = assinaturaService.iniciarTesteEssencial(conta.id());
            return ResponseEntity.ok(assinatura);
        } catch (IllegalStateException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage());
        }
    }

    @GetMapping("/consumo")
    public ResponseEntity<Map<String, Object>> consultarConsumo(Authentication authentication) {
        ContaAutenticada conta = obterConta(authentication);
        Assinatura assinatura = assinaturaService.obterOuCriarGratuita(conta.tipo(), conta.id());
        LocalDateTime agora = LocalDateTime.now(FUSO);

        if (conta.tipo() == Assinatura.TipoConta.ENTREGADOR) {
            return ResponseEntity.ok(consultarConsumoEntregador(conta.id(), assinatura, agora.toLocalDate()));
        }

        return ResponseEntity.ok(consultarConsumoEmpresa(conta.id(), assinatura, agora));
    }

    private Map<String, Object> consultarConsumoEntregador(
            Long entregadorId, Assinatura assinatura, LocalDate hoje
    ) {
        Usuario entregador = usuarioRepository.findById(entregadorId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "Entregador não encontrado"
                ));

        LocalDateTime inicio = hoje.atStartOfDay();
        LocalDateTime fim = hoje.plusDays(1).atStartOfDay();
        long entregasUtilizadas = entregaRepository.contarEntregasAutonomasNoPeriodo(
                entregador, inicio, fim
        );

        Integer limiteEntregas = switch (assinatura.getPlano()) {
            case GRATUITO -> 20;
            case ESSENCIAL -> 50;
            case PROFISSIONAL -> null;
        };
        boolean ilimitadas = limiteEntregas == null;
        Long disponiveis = ilimitadas ? null : Math.max(0L, limiteEntregas - entregasUtilizadas);

        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("tipoConta", Assinatura.TipoConta.ENTREGADOR.name());
        resultado.put("plano", assinatura.getPlano().name());
        resultado.put("status", assinatura.getStatus().name());
        resultado.put("testeGratuito", false);
        resultado.put("periodo", "DIARIO");
        resultado.put("dataReferencia", hoje.toString());
        resultado.put("inicioPeriodo", hoje.toString());
        resultado.put("fimPeriodoExclusivo", hoje.plusDays(1).toString());
        resultado.put("inicioPeriodoDataHora", inicio.toString());
        resultado.put("fimPeriodoExclusivoDataHora", fim.toString());
        resultado.put("entregasUtilizadasHoje", entregasUtilizadas);
        resultado.put("limiteEntregasDia", limiteEntregas);
        resultado.put("entregasDisponiveisHoje", disponiveis);
        resultado.put("entregasUtilizadasPeriodo", entregasUtilizadas);
        resultado.put("limiteEntregasPeriodo", limiteEntregas);
        resultado.put("entregasDisponiveisPeriodo", disponiveis);
        resultado.put("entregasIlimitadas", ilimitadas);
        return resultado;
    }

    private Map<String, Object> consultarConsumoEmpresa(
            Long empresaId, Assinatura assinatura, LocalDateTime agora
    ) {
        LocalDate hoje = agora.toLocalDate();
        LocalDate inicioMes = hoje.withDayOfMonth(1);
        LocalDate inicioProximoMes = inicioMes.plusMonths(1);

        boolean emTeste = assinatura.isTesteGratuito()
                && assinatura.getStatus() == Assinatura.Status.ATIVA
                && assinatura.getDataInicio() != null
                && assinatura.getDataVencimento() != null
                && !assinatura.getDataInicio().isAfter(agora)
                && assinatura.getDataVencimento().isAfter(agora);

        LocalDateTime inicio = emTeste
                ? assinatura.getDataInicio()
                : inicioMes.atStartOfDay();
        LocalDateTime fim = emTeste
                ? assinatura.getDataVencimento()
                : inicioProximoMes.atStartOfDay();

        int limiteEntregas = emTeste ? 500 : limiteMensal(assinatura.getPlano());

        Map<String, Object> resultado = new LinkedHashMap<>();
        resultado.put("tipoConta", Assinatura.TipoConta.EMPRESA.name());
        resultado.put("plano", assinatura.getPlano().name());
        resultado.put("status", assinatura.getStatus().name());
        resultado.put("testeGratuito", emTeste);
        resultado.put("periodo", emTeste ? "TESTE" : "MENSAL");
        resultado.put("dataReferencia", hoje.toString());
        resultado.put("inicioPeriodo", emTeste ? inicio.toString() : inicioMes.toString());
        resultado.put("fimPeriodoExclusivo", emTeste ? fim.toString() : inicioProximoMes.toString());
        resultado.put("inicioPeriodoDataHora", inicio.toString());
        resultado.put("fimPeriodoExclusivoDataHora", fim.toString());

        if (emTeste) {
            resultado.put("dataInicioTeste", assinatura.getDataInicio().toString());
            resultado.put("dataFimTeste", assinatura.getDataVencimento().toString());
        }

        Empresa empresa = empresaRepository.findById(empresaId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "Empresa não encontrada"
                ));

        long entregasUtilizadas = entregaRepository.contarEntregasEmpresaNoPeriodo(
                empresa, inicio, fim
        );

        long vinculados = usuarioRepository.countByEmpresa(empresa);
        long pendentes = usuarioRepository.findByEmpresaPendente(empresa).size();
        long ocupadas = vinculados + pendentes;
        int limiteEntregadores = limiteEntregadores(assinatura.getPlano());

        resultado.put("entregadoresVinculados", vinculados);
        resultado.put("solicitacoesPendentes", pendentes);
        resultado.put("vagasOcupadas", ocupadas);
        resultado.put("limiteEntregadores", limiteEntregadores);
        resultado.put("vagasDisponiveis", Math.max(0L, limiteEntregadores - ocupadas));
        resultado.put("entregasUtilizadasMes", entregasUtilizadas);
        resultado.put("limiteEntregasMes", limiteEntregas);
        resultado.put("entregasDisponiveisMes", Math.max(0L, limiteEntregas - entregasUtilizadas));
        resultado.put("entregasUtilizadasPeriodo", entregasUtilizadas);
        resultado.put("limiteEntregasPeriodo", limiteEntregas);
        resultado.put("entregasDisponiveisPeriodo", Math.max(0L, limiteEntregas - entregasUtilizadas));
        resultado.put("entregasIlimitadas", false);
        return resultado;
    }

    private int limiteMensal(Assinatura.Plano plano) {
        return switch (plano) {
            case GRATUITO -> 100;
            case ESSENCIAL -> 1000;
            case PROFISSIONAL -> 5000;
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
        if (partes.length != 2 || !partes[1].matches("[0-9]+")) {
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
