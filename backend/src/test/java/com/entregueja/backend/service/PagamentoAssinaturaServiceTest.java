package com.entregueja.backend.service;

import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import jakarta.persistence.TypedQuery;
import com.entregueja.backend.entity.Assinatura;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class PagamentoAssinaturaServiceTest {

    @Mock
    private PagamentoAssinaturaRepository pagamentoRepository;
    @Mock
    private AssinaturaRecorrenteRepository recorrenteRepository;
    @Mock
    private MercadoPagoService mercadoPagoService;
    @Mock
    private AssinaturaService assinaturaService;
    @Mock
    private EntityManager entityManager;
    @InjectMocks
    private PagamentoAssinaturaService service;

    private final ObjectMapper mapper = new ObjectMapper();
    private AssinaturaRecorrente recorrente;
    private Assinatura assinaturaAtual;

    @BeforeEach
    void preparar() {
        recorrente = new AssinaturaRecorrente();
        recorrente.setEmpresaId(10L);
        recorrente.setPlano(com.entregueja.backend.entity.Assinatura.Plano.ESSENCIAL);
        recorrente.setValor(new BigDecimal("39.90"));
        recorrente.setMercadoPagoAssinaturaId("sub123");
    }

    private JsonNode json(String conteudo) {
        try {
            return mapper.readTree(conteudo);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private void prepararConsulta(String status, String valorPagamento, String referenciaAssinatura) {
        lenient().when(mercadoPagoService.consultarPagamento("12345")).thenReturn(json("""
                {"id":"12345","preapproval_id":"%s","transaction_amount":%s,
                "currency_id":"BRL","payment_type_id":"credit_card","status":"%s"}
                """.formatted(referenciaAssinatura, valorPagamento, status)));
        lenient().when(recorrenteRepository.findByMercadoPagoAssinaturaId("sub123"))
                .thenReturn(Optional.of(recorrente));
        Empresa empresa = new Empresa();
        empresa.setId(10L);
        @SuppressWarnings("unchecked")
        TypedQuery<Assinatura> consulta = mock(TypedQuery.class);
        lenient().when(entityManager.createQuery(anyString(), eq(Assinatura.class))).thenReturn(consulta);
        lenient().when(consulta.setParameter(anyString(), any())).thenReturn(consulta);
        lenient().when(consulta.setMaxResults(1)).thenReturn(consulta);
        lenient().when(consulta.getResultStream()).thenAnswer(invocacao -> assinaturaAtual == null ? Stream.empty() : Stream.of(assinaturaAtual));
        lenient().when(entityManager.find(eq(Empresa.class), eq(10L), eq(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)))
                .thenReturn(empresa);
        lenient().when(mercadoPagoService.consultarAssinaturaRecorrente("sub123")).thenReturn(json("""
                {"id":"sub123","external_reference":"entregueja-recorrente-null",
                "auto_recurring":{"transaction_amount":39.90,"currency_id":"BRL"}}
                """));
    }

    @Test
    void rejeitaIdentificadorDePagamentoInvalido() {
        assertThrows(IllegalArgumentException.class, () -> service.processarPagamentoRecorrente("abc"));
        verifyNoInteractions(mercadoPagoService, assinaturaService);
    }

    @Test
    void rejeitaPagamentoSemVinculoComAssinatura() {
        when(mercadoPagoService.consultarPagamento("12345")).thenReturn(json("""
                {"id":"12345","transaction_amount":39.90,"status":"approved"}
                """));
        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void rejeitaValorDivergenteSemAtivarPlano() {
        prepararConsulta("approved", "79.90", "sub123");
        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pagamentoRecusadoNaoAtivaPlano() {
        prepararConsulta("rejected", "39.90", "sub123");
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamentoExistente()));
        Map<String, Object> resultado = service.processarPagamentoRecorrente("12345");
        assertEquals("RECUSADO", resultado.get("status"));
        assertEquals(false, resultado.get("planoAtivado"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pagamentoAprovadoSolicitaAtivacaoUmaVez() {
        prepararConsulta("approved", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setId(99L);
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));
        Map<String, Object> resultado = service.processarPagamentoRecorrente("12345");
        assertEquals("APROVADO", resultado.get("status"));
        verify(assinaturaService, times(1)).ativarPlanoPagoPorCartao(10L, 99L);
    }

    @Test
    void pagamentoJaAtivadoNaoRenovaNovamente() {
        prepararConsulta("approved", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setId(99L);
        pagamento.setStatus(PagamentoAssinatura.Status.APROVADO);
        pagamento.setDataVencimento(LocalDateTime.now().plusDays(20));
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));

        Map<String, Object> primeira = service.processarPagamentoRecorrente("12345");
        Map<String, Object> segunda = service.processarPagamentoRecorrente("12345");

        assertEquals("APROVADO", primeira.get("status"));
        assertEquals(true, segunda.get("planoAtivado"));
        verify(assinaturaService, never()).ativarPlanoPagoPorCartao(anyLong(), anyLong());
    }

    @Test
    void webhookDuplicadoDePagamentoPendenteNaoAtivaPlano() {
        prepararConsulta("pending", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setId(99L);
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));

        service.processarPagamentoRecorrente("12345");
        service.processarPagamentoRecorrente("12345");

        assertEquals(PagamentoAssinatura.Status.PENDENTE, pagamento.getStatus());
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pagamentoDeOutraEmpresaNaoAtivaPlano() {
        prepararConsulta("approved", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setEmpresaId(20L);
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pagamentoDeOutraAssinaturaNaoAtivaPlano() {
        prepararConsulta("approved", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setMercadoPagoAssinaturaId("outra-assinatura");
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void trocaAgendadaAntesDoVencimentoBloqueiaProcessamento() {
        prepararConsulta("approved", "39.90", "sub123");
        Assinatura assinatura = new Assinatura();
        assinatura.setPlano(Assinatura.Plano.ESSENCIAL);
        assinatura.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        assinatura.setDataVencimento(LocalDateTime.now().plusDays(10));
        assinatura.setDataTrocaAgendada(assinatura.getDataVencimento());
        assinatura.setMercadoPagoAssinaturaId("sub123");

        assinaturaAtual = assinatura;

        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void falhaNaAtivacaoNaoMarcaPagamentoComoAtivado() {
        prepararConsulta("approved", "39.90", "sub123");
        PagamentoAssinatura pagamento = pagamentoExistente();
        pagamento.setId(99L);
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345"))
                .thenReturn(Optional.of(pagamento));
        doThrow(new IllegalStateException("Falha simulada"))
                .when(assinaturaService).ativarPlanoPagoPorCartao(10L, 99L);

        assertThrows(IllegalStateException.class, () -> service.processarPagamentoRecorrente("12345"));
        assertNull(pagamento.getDataVencimento());
    }

    private PagamentoAssinatura pagamentoExistente() {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(10L);
        pagamento.setPlano(com.entregueja.backend.entity.Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setValor(new BigDecimal("39.90"));
        pagamento.setMercadoPagoPagamentoId("12345");
        pagamento.setMercadoPagoAssinaturaId("sub123");
        return pagamento;
    }
}
