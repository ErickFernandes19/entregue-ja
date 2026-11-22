package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AssinaturaRecorrenteServiceTest {

    @Mock
    private AssinaturaRecorrenteRepository repository;
    @Mock
    private MercadoPagoService mercadoPagoService;
    @Mock
    private PagamentoAssinaturaRepository pagamentoRepository;
    @Mock
    private PagamentoAssinaturaService pagamentoService;
    @Mock
    private EntityManager entityManager;

    private AssinaturaRecorrenteService service;
    private final ObjectMapper mapper = new ObjectMapper();
    private final String chave = UUID.randomUUID().toString();

    @BeforeEach
    void preparar() {
        service = new AssinaturaRecorrenteService(
                repository, mercadoPagoService, pagamentoRepository,
                pagamentoService, entityManager, "https://exemplo.com/retorno"
        );
        Empresa empresa = new Empresa();
        empresa.setId(10L);
        empresa.setEmail("empresa@exemplo.com");
        lenient().when(entityManager.find(Empresa.class, 10L, LockModeType.PESSIMISTIC_WRITE))
                .thenReturn(empresa);
    }

    private AssinaturaRecorrente registro(String email) {
        AssinaturaRecorrente registro = new AssinaturaRecorrente();
        registro.setId(55L);
        registro.setEmpresaId(10L);
        registro.setPlano(Assinatura.Plano.ESSENCIAL);
        registro.setValor(new BigDecimal("39.90"));
        registro.setEmailPagador(email);
        registro.setChaveIdempotencia(chave);
        registro.setStatus(AssinaturaRecorrente.Status.PENDENTE);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.PREPARADA);
        return registro;
    }

    private void prepararCriacao() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(AssinaturaRecorrente.class))).thenAnswer(invocacao -> {
            AssinaturaRecorrente salvo = invocacao.getArgument(0);
            salvo.setId(55L);
            return salvo;
        });
        lenient().when(repository.save(any(AssinaturaRecorrente.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));
    }

    @Test
    void criaAssinaturaComEmailDoPagadorEDonoEmpresa() throws Exception {
        prepararCriacao();
        when(mercadoPagoService.criarAssinaturaRecorrente(
                anyString(), eq("pagador@exemplo.com"),
                eq("entregueja-recorrente-55"), eq(new BigDecimal("39.90")), anyString()
        )).thenReturn(mapper.readTree("""
                {"id":"sub55","external_reference":"entregueja-recorrente-55",
                "init_point":"https://exemplo.com/autorizacao","status":"pending"}
                """));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, " pagador@exemplo.com "
        );

        assertEquals(55L, resultado.get("assinaturaId"));
        assertEquals("sub55", resultado.get("mercadoPagoAssinaturaId"));
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        var captor = org.mockito.ArgumentCaptor.forClass(AssinaturaRecorrente.class);
        verify(repository).saveAndFlush(captor.capture());
        assertEquals(10L, captor.getValue().getEmpresaId());
        assertEquals("pagador@exemplo.com", captor.getValue().getEmailPagador());
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(
                anyString(), eq("pagador@exemplo.com"), anyString(), any(), anyString()
        );
    }

    @Test
    void mesmaChaveMesmosDadosRecuperaAssinaturaSemNovaCobranca() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "PAGADOR@EXEMPLO.COM"
        );

        assertEquals(55L, resultado.get("assinaturaId"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void mesmaChaveComOutroEmailEhRejeitada() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "outro@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void mesmaChaveDeOutraEmpresaEhRejeitada() {
        AssinaturaRecorrente existente = registro("pagador@exemplo.com");
        existente.setEmpresaId(20L);
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(existente));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void registroAntigoSemEmailEhRejeitado() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro(null)));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void emailInvalidoEhRejeitadoAntesDeCriarAssinatura() {
        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "invalido"
        ));
        verifyNoInteractions(repository, mercadoPagoService);
    }

    @Test
    void falhaDeComunicacaoMarcaTentativaComoIncerta() {
        prepararCriacao();
        when(mercadoPagoService.criarAssinaturaRecorrente(
                anyString(), anyString(), anyString(), any(), anyString()
        )).thenThrow(new IllegalStateException("Falha de comunicação"));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));

        var captor = org.mockito.ArgumentCaptor.forClass(AssinaturaRecorrente.class);
        verify(repository, atLeastOnce()).save(captor.capture());
        assertEquals(AssinaturaRecorrente.EstadoCriacao.INCERTA,
                captor.getAllValues().get(captor.getAllValues().size() - 1).getEstadoCriacao());
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(
                anyString(), anyString(), anyString(), any(), anyString()
        );
    }

    @Test
    void tentativaIncertaExistenteBloqueiaNovaChave() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        AssinaturaRecorrente incerta = registro("pagador@exemplo.com");
        incerta.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.of(incerta));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void mesmaChaveIncertaNaoReenviaAoMercadoPago() {
        AssinaturaRecorrente incerta = registro("pagador@exemplo.com");
        incerta.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(incerta));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        );

        assertEquals("INCERTA", resultado.get("estadoCriacao"));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void erroNaGravacaoInicialNaoChamaMercadoPago() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(AssinaturaRecorrente.class)))
                .thenThrow(new IllegalStateException("Falha no banco"));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }
}
