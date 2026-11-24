package com.entregueja.backend.service;

import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.persistence.TypedQuery;
import com.entregueja.backend.entity.Assinatura;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
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
    @Mock
    private PlatformTransactionManager transactionManager;
    @InjectMocks
    private PagamentoAssinaturaService service;

    private final ObjectMapper mapper = new ObjectMapper();
    private AssinaturaRecorrente recorrente;
    private Assinatura assinaturaAtual;

    @BeforeEach
    void preparar() {
        lenient().when(transactionManager.getTransaction(any(TransactionDefinition.class)))
                .thenAnswer(invocacao -> {
                    TransactionDefinition definicao = invocacao.getArgument(0);
                    assertEquals(TransactionDefinition.PROPAGATION_REQUIRES_NEW, definicao.getPropagationBehavior());
                    return new SimpleTransactionStatus();
                });
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
        lenient().when(mercadoPagoService.consultarPagamentoRecorrente("12345")).thenReturn(json("""
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
        when(mercadoPagoService.consultarPagamentoRecorrente("12345")).thenReturn(json("""
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


    @Test
    void pixAprovadoSolicitaAtivacaoDoPlano() {
        PagamentoAssinatura pagamento = prepararPagamentoPix("approved", "39.90");

        Map<String, Object> resultado = service.consultarCobrancaPix(10L, 99L);

        assertEquals("APROVADO", resultado.get("status"));
        assertEquals(PagamentoAssinatura.Status.APROVADO, pagamento.getStatus());
        assertNotNull(pagamento.getDataAprovacao());
        verify(assinaturaService, times(1)).ativarPlanoPagoPorPix(10L, 99L);
    }

    @Test
    void pixPendenteNaoSolicitaAtivacao() {
        PagamentoAssinatura pagamento = prepararPagamentoPix("pending", "39.90");

        Map<String, Object> resultado = service.consultarCobrancaPix(10L, 99L);

        assertEquals("PENDENTE", resultado.get("status"));
        assertEquals(PagamentoAssinatura.Status.PENDENTE, pagamento.getStatus());
        verify(assinaturaService, never()).ativarPlanoPagoPorPix(anyLong(), anyLong());
    }

    @Test
    void pixJaAtivadoNaoSolicitaNovaAtivacao() {
        PagamentoAssinatura pagamento = prepararPagamentoPix("approved", "39.90");
        pagamento.setStatus(PagamentoAssinatura.Status.APROVADO);
        pagamento.setDataAprovacao(LocalDateTime.now());
        pagamento.setDataVencimento(LocalDateTime.now().plusDays(30));

        Map<String, Object> primeira = service.consultarCobrancaPix(10L, 99L);
        Map<String, Object> segunda = service.consultarCobrancaPix(10L, 99L);

        assertEquals("APROVADO", primeira.get("status"));
        assertEquals(true, segunda.get("planoAtivado"));
        verify(assinaturaService, never()).ativarPlanoPagoPorPix(anyLong(), anyLong());
    }

    @Test
    void pixComValorIncorretoNaoAtivaPlano() {
        prepararPagamentoPix("approved", "79.90");

        assertThrows(IllegalStateException.class,
                () -> service.consultarCobrancaPix(10L, 99L));

        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pixComReferenciaIncorretaNaoAtivaPlano() {
        prepararPagamentoPix("approved", "39.90");

        when(mercadoPagoService.consultarPagamento("12345"))
                .thenReturn(json("""
                        {
                          "id": "12345",
                          "external_reference": "entregueja-pagamento-999",
                          "transaction_amount": 39.90,
                          "currency_id": "BRL",
                          "payment_method_id": "pix",
                          "status": "approved"
                        }
                        """));

        assertThrows(IllegalStateException.class,
                () -> service.consultarCobrancaPix(10L, 99L));

        verifyNoInteractions(assinaturaService);
    }

    @Test
    void pixComIdentificadorIncorretoNaoAtivaPlano() {
        prepararPagamentoPix("approved", "39.90");

        when(mercadoPagoService.consultarPagamento("12345"))
                .thenReturn(json("""
                        {
                          "id": "98765",
                          "external_reference": "entregueja-pagamento-99",
                          "transaction_amount": 39.90,
                          "currency_id": "BRL",
                          "payment_method_id": "pix",
                          "status": "approved"
                        }
                        """));

        assertThrows(IllegalStateException.class,
                () -> service.consultarCobrancaPix(10L, 99L));

        verifyNoInteractions(assinaturaService);
    }

    @Test
    void falhaNaAtivacaoPixNaoMarcaPlanoComoAtivado() {
        PagamentoAssinatura pagamento = prepararPagamentoPix("approved", "39.90");

        doThrow(new IllegalStateException("Falha simulada"))
                .when(assinaturaService).ativarPlanoPagoPorPix(10L, 99L);

        assertThrows(IllegalStateException.class,
                () -> service.consultarCobrancaPix(10L, 99L));

        assertNull(pagamento.getDataVencimento());
    }

    private PagamentoAssinatura prepararPagamentoPix(
            String statusExterno,
            String valorExterno) {

        Empresa empresa = new Empresa();
        empresa.setId(10L);
        empresa.setEmail("empresa@exemplo.com");

        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setId(99L);
        pagamento.setEmpresaId(10L);
        pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setValor(new BigDecimal("39.90"));
        pagamento.setMercadoPagoPagamentoId("12345");

        lenient().when(entityManager.find(Empresa.class, 10L))
                .thenReturn(empresa);

        lenient().when(entityManager.find(
                        Empresa.class,
                        10L,
                        jakarta.persistence.LockModeType.PESSIMISTIC_WRITE))
                .thenReturn(empresa);

        lenient().when(pagamentoRepository.buscarPorIdComBloqueio(99L))
                .thenReturn(Optional.of(pagamento));

        lenient().when(mercadoPagoService.consultarPagamento("12345"))
                .thenReturn(json("""
                        {
                          "id": "12345",
                          "external_reference": "entregueja-pagamento-99",
                          "transaction_amount": %s,
                          "currency_id": "BRL",
                          "payment_method_id": "pix",
                          "status": "%s"
                        }
                        """.formatted(valorExterno, statusExterno)));

        return pagamento;
    }

    private static final String CHAVE_PIX = "a60c8bd1-48ce-42c5-b817-17c1139b8910";
    private static final String CHAVE_ANTERIOR = "d91a2a18-c280-4ad2-9f09-d76ca9a0c981";

    @Test
    void pixEmpresaComRecorrentePendenteBloqueiaNovaCobranca() {
        verificarBloqueioRecorrente(Assinatura.TipoConta.EMPRESA, AssinaturaRecorrente.Status.PENDENTE);
    }

    @Test
    void pixEntregadorComRecorrenteAutorizadaBloqueiaNovaCobranca() {
        verificarBloqueioRecorrente(Assinatura.TipoConta.ENTREGADOR, AssinaturaRecorrente.Status.AUTORIZADA);
    }

    @Test
    void pixEntregadorComRecorrentePausadaBloqueiaNovaCobranca() {
        verificarBloqueioRecorrente(Assinatura.TipoConta.ENTREGADOR, AssinaturaRecorrente.Status.PAUSADA);
    }

    @Test
    void pixComTentativaRecorrenteIncertaBloqueiaNovaCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        AssinaturaRecorrente tentativa = new AssinaturaRecorrente();
        tentativa.setEntregadorId(10L);
        tentativa.setStatus(AssinaturaRecorrente.Status.CANCELADA);
        tentativa.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        when(recorrenteRepository.findFirstByEntregadorIdAndEstadoCriacaoInOrderByIdDesc(
                10L, List.of(AssinaturaRecorrente.EstadoCriacao.PREPARADA,
                        AssinaturaRecorrente.EstadoCriacao.ENVIANDO,
                        AssinaturaRecorrente.EstadoCriacao.INCERTA)))
                .thenReturn(Optional.of(tentativa));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> criarPix(Assinatura.TipoConta.ENTREGADOR));

        assertTrue(erro.getMessage().contains("tentativa não resolvida"));
        verificarSemNovaCobranca();
    }

    @Test
    void pixEmpresaComOutroPixPendenteBloqueiaNovaCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura anterior = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        anterior.setChaveIdempotencia(CHAVE_ANTERIOR);
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(anterior));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> criarPix(Assinatura.TipoConta.EMPRESA));

        assertTrue(erro.getMessage().contains("cobrança não resolvida"));
        verificarSemNovaCobranca();
    }

    @Test
    void pixEntregadorComPagamentoAprovadoSemAtivacaoBloqueiaNovaCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        PagamentoAssinatura anterior = pixParaCriacao(Assinatura.TipoConta.ENTREGADOR);
        anterior.setChaveIdempotencia(CHAVE_ANTERIOR);
        anterior.setStatus(PagamentoAssinatura.Status.APROVADO);
        anterior.setDataAprovacao(LocalDateTime.now());
        when(pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(anterior));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> criarPix(Assinatura.TipoConta.ENTREGADOR));

        assertTrue(erro.getMessage().contains("cobrança não resolvida"));
        verificarSemNovaCobranca();
    }

    @Test
    void mesmaChaveRecuperaPixExistenteSemCriarOutraCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        PagamentoAssinatura pagamento = pixParaCriacao(Assinatura.TipoConta.ENTREGADOR);
        when(pagamentoRepository.findByChaveIdempotencia(CHAVE_PIX)).thenReturn(Optional.of(pagamento));
        when(pagamentoRepository.buscarPorIdComBloqueio(99L)).thenReturn(Optional.of(pagamento));
        when(mercadoPagoService.consultarPagamento("12345")).thenReturn(respostaPix("9.90", "pending"));

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.ENTREGADOR);

        assertEquals(99L, resultado.get("pagamentoId"));
        assertEquals("PENDENTE", resultado.get("status"));
        verify(mercadoPagoService).consultarPagamento("12345");
        verify(mercadoPagoService, never()).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
        verifyNoInteractions(assinaturaService);
        verifyNoInteractions(recorrenteRepository);
    }

    @Test
    void empresaNaoPodeReutilizarChaveDeEntregadorComMesmoId() {
        verificarChaveDeOutroPerfil(Assinatura.TipoConta.EMPRESA, Assinatura.TipoConta.ENTREGADOR);
    }

    @Test
    void entregadorNaoPodeReutilizarChaveDeEmpresaComMesmoId() {
        verificarChaveDeOutroPerfil(Assinatura.TipoConta.ENTREGADOR, Assinatura.TipoConta.EMPRESA);
    }

    @Test
    void criaPixEntregadorComPrecoETitularidadeCorretos() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(eq(new BigDecimal("9.90")),
                eq("Assinatura Entregue Já - ESSENCIAL"), eq("entregador@exemplo.com"),
                eq("entregueja-pagamento-99"), eq(CHAVE_PIX)))
                .thenReturn(respostaPix("9.90", "pending"));

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.ENTREGADOR);

        assertEquals("PENDENTE", resultado.get("status"));
        assertEquals(new BigDecimal("9.90"), resultado.get("valor"));
        assertEquals(99L, resultado.get("pagamentoId"));
        ArgumentCaptor<PagamentoAssinatura> captor = ArgumentCaptor.forClass(PagamentoAssinatura.class);
        verify(pagamentoRepository, times(2)).saveAndFlush(captor.capture());
        for (PagamentoAssinatura pagamento : captor.getAllValues()) {
            assertEquals(10L, pagamento.getEntregadorId());
            assertNull(pagamento.getEmpresaId());
            assertEquals(CHAVE_PIX, pagamento.getChaveIdempotencia());
            assertEquals(PagamentoAssinatura.FormaPagamento.PIX, pagamento.getFormaPagamento());
        }
        verify(mercadoPagoService, times(1)).criarPagamentoPix(eq(new BigDecimal("9.90")),
                anyString(), anyString(), eq("entregueja-pagamento-99"), eq(CHAVE_PIX));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void mesmaChaveRecuperaTentativaPixSemReenviarCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        when(pagamentoRepository.findByChaveIdempotencia(CHAVE_PIX)).thenReturn(Optional.of(pagamento));
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.of(respostaPix("39.90", "pending")));

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.EMPRESA);

        assertEquals(99L, resultado.get("pagamentoId"));
        assertEquals("12345", pagamento.getMercadoPagoPagamentoId());
        assertEquals(CHAVE_PIX, pagamento.getChaveIdempotencia());
        assertEquals(true, resultado.get("buscaReferenciaRealizada"));
        verify(pagamentoRepository).saveAndFlush(pagamento);
        verificarSemEnvioPix();
        verifyNoInteractions(assinaturaService, recorrenteRepository);
    }

    @Test
    void pixAnteriorAtivadoNaoBloqueiaNovaCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura anterior = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        anterior.setChaveIdempotencia(CHAVE_ANTERIOR);
        anterior.setStatus(PagamentoAssinatura.Status.APROVADO);
        anterior.setDataAprovacao(LocalDateTime.now().minusDays(30));
        anterior.setDataVencimento(LocalDateTime.now().minusDays(1));
        anterior.setId(98L);
        anterior.setMercadoPagoPagamentoId("12344");
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L)).thenReturn(List.of(anterior));
        prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(eq(new BigDecimal("39.90")),
                anyString(), eq("empresa@exemplo.com"), eq("entregueja-pagamento-99"), eq(CHAVE_PIX)))
                .thenReturn(respostaPix("39.90", "pending"));

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.EMPRESA);

        assertEquals(99L, resultado.get("pagamentoId"));
        assertEquals("PENDENTE", resultado.get("status"));
        verify(mercadoPagoService, times(1)).criarPagamentoPix(eq(new BigDecimal("39.90")),
                anyString(), eq("empresa@exemplo.com"), eq("entregueja-pagamento-99"), eq(CHAVE_PIX));
    }

    @Test
    void novaTentativaConfirmaRegistroAntesDoEnvioExterno() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        AtomicReference<PagamentoAssinatura> registro = prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString()))
                .thenAnswer(invocacao -> {
                    verify(transactionManager, times(1)).commit(any(TransactionStatus.class));
                    PagamentoAssinatura pagamento = registro.get();
                    assertNotNull(pagamento);
                    assertEquals(99L, pagamento.getId());
                    assertEquals(CHAVE_PIX, pagamento.getChaveIdempotencia());
                    assertEquals(PagamentoAssinatura.Status.PENDENTE, pagamento.getStatus());
                    assertNull(pagamento.getMercadoPagoPagamentoId());
                    return respostaPix("39.90", "pending");
                });

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.EMPRESA);

        assertEquals("12345", resultado.get("mercadoPagoPagamentoId"));
        verify(transactionManager, times(3)).commit(any(TransactionStatus.class));
        verify(transactionManager, never()).rollback(any(TransactionStatus.class));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void falhaNaConfirmacaoDoRegistroImpedeEnvioExterno() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        prepararRegistroNovaTentativa();
        doThrow(new IllegalStateException("Falha no commit"))
                .when(transactionManager).commit(any(TransactionStatus.class));

        assertThrows(IllegalStateException.class, () -> criarPix(Assinatura.TipoConta.EMPRESA));

        verify(transactionManager).commit(any(TransactionStatus.class));
        verifyNoInteractions(mercadoPagoService, assinaturaService);
    }

    @Test
    void falhaExternaAposRegistroNaoReenviaPixComMesmaChave() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        AtomicReference<PagamentoAssinatura> registro = prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString()))
                .thenThrow(new MercadoPagoService.MercadoPagoException("Falha simulada", null));

        assertThrows(MercadoPagoService.MercadoPagoException.class,
                () -> criarPix(Assinatura.TipoConta.EMPRESA));

        verify(transactionManager).commit(any(TransactionStatus.class));
        verify(transactionManager, never()).rollback(any(TransactionStatus.class));
        PagamentoAssinatura pagamento = registro.get();
        assertNotNull(pagamento);
        assertEquals(PagamentoAssinatura.Status.PENDENTE, pagamento.getStatus());
        assertNull(pagamento.getMercadoPagoPagamentoId());
        when(pagamentoRepository.findByChaveIdempotencia(CHAVE_PIX)).thenReturn(Optional.of(pagamento));
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.empty());

        Map<String, Object> resultado = criarPix(Assinatura.TipoConta.EMPRESA);

        assertEquals("AGUARDANDO_IDENTIFICACAO", resultado.get("situacaoRecuperacao"));
        assertEquals(true, resultado.get("buscaReferenciaRealizada"));
        assertEquals(true, resultado.get("requerConciliacao"));
        verify(mercadoPagoService, times(1)).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
        verify(pagamentoRepository, times(1)).saveAndFlush(any(PagamentoAssinatura.class));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void respostaSemIdentificadorMantemRegistroInicialConfirmado() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        AtomicReference<PagamentoAssinatura> registro = prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(json("{\"status\":\"pending\"}"));

        assertThrows(IllegalStateException.class, () -> criarPix(Assinatura.TipoConta.ENTREGADOR));

        verify(transactionManager).commit(any(TransactionStatus.class));
        verify(transactionManager, never()).rollback(any(TransactionStatus.class));
        assertEquals(PagamentoAssinatura.Status.PENDENTE, registro.get().getStatus());
        assertNull(registro.get().getMercadoPagoPagamentoId());
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void falhaNaAtivacaoDeNovaCobrancaOcorreDepoisDaConfirmacaoDoStatus() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        AtomicReference<PagamentoAssinatura> registro = prepararRegistroNovaTentativa();
        when(mercadoPagoService.criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(respostaPix("39.90", "approved"));
        doAnswer(invocacao -> {
            verify(transactionManager, times(2)).commit(any(TransactionStatus.class));
            assertEquals(PagamentoAssinatura.Status.APROVADO, registro.get().getStatus());
            assertEquals("12345", registro.get().getMercadoPagoPagamentoId());
            throw new IllegalStateException("Falha de ativação simulada");
        }).when(assinaturaService).ativarPlanoPagoPorPix(10L, 99L);

        assertThrows(IllegalStateException.class, () -> criarPix(Assinatura.TipoConta.EMPRESA));

        verify(transactionManager, times(2)).commit(any(TransactionStatus.class));
        verify(transactionManager).rollback(any(TransactionStatus.class));
        assertNull(registro.get().getDataVencimento());
    }

    @Test
    void pixRecuperadoAprovadoAtivaPlanoDoEntregadorUmaVez() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.ENTREGADOR);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("9.90")))
                .thenReturn(Optional.of(respostaPix("9.90", "approved")));
        when(mercadoPagoService.consultarPagamento("12345")).thenReturn(respostaPix("9.90", "approved"));
        LocalDateTime vencimento = LocalDateTime.now().plusDays(30);
        doAnswer(invocacao -> {
            pagamento.setDataVencimento(vencimento);
            return null;
        }).when(assinaturaService).ativarPlanoPagoPorPix(Assinatura.TipoConta.ENTREGADOR, 10L, 99L);

        Map<String, Object> primeira = service.consultarCobrancaPix(Assinatura.TipoConta.ENTREGADOR, 10L, 99L);
        Map<String, Object> segunda = service.consultarCobrancaPix(Assinatura.TipoConta.ENTREGADOR, 10L, 99L);

        assertEquals("APROVADO", primeira.get("status"));
        assertEquals("ENTREGADOR", primeira.get("tipoConta"));
        assertEquals(true, primeira.get("buscaReferenciaRealizada"));
        assertEquals(true, segunda.get("planoAtivado"));
        assertEquals(vencimento, segunda.get("vencimentoPlano"));
        verify(assinaturaService, times(1)).ativarPlanoPagoPorPix(Assinatura.TipoConta.ENTREGADOR, 10L, 99L);
        verificarSemEnvioPix();
    }

    @Test
    void buscaSemResultadoNaoLiberaNovaChave() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.empty());
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L)).thenReturn(List.of(pagamento));

        Map<String, Object> resultado = service.consultarCobrancaPix(10L, 99L);
        assertEquals("PENDENTE", resultado.get("status"));
        assertEquals(true, resultado.get("requerConciliacao"));
        assertEquals(false, resultado.get("consultaMercadoPagoRealizada"));
        assertThrows(IllegalStateException.class, () -> service.criarCobrancaPix(10L, Assinatura.Plano.ESSENCIAL, CHAVE_ANTERIOR));
        verificarSemEnvioPix();
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void buscaAmbiguaNaoVinculaNemAtivaPagamento() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenThrow(new MercadoPagoService.MercadoPagoException("Referência ambígua", null));

        assertThrows(MercadoPagoService.MercadoPagoException.class, () -> service.consultarCobrancaPix(10L, 99L));
        assertNull(pagamento.getMercadoPagoPagamentoId());
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verificarSemEnvioPix();
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void recuperacaoRejeitaIdentificadorVinculadoAOutraCobranca() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura outro = pixParaCriacao(Assinatura.TipoConta.ENTREGADOR);
        outro.setId(100L);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.of(respostaPix("39.90", "approved")));
        when(pagamentoRepository.buscarPorMercadoPagoPagamentoIdComBloqueio("12345")).thenReturn(Optional.of(outro));

        assertThrows(IllegalStateException.class, () -> service.consultarCobrancaPix(10L, 99L));
        assertNull(pagamento.getMercadoPagoPagamentoId());
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verificarSemEnvioPix();
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void recuperacaoRejeitaValorExternoDivergente() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.of(respostaPix("79.90", "approved")));

        assertThrows(IllegalStateException.class, () -> service.consultarCobrancaPix(10L, 99L));
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verificarSemEnvioPix();
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void recuperacaoRejeitaIdentificadorExternoInvalido() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura pagamento = prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);
        when(mercadoPagoService.buscarPagamentoPixPorReferencia("entregueja-pagamento-99", new BigDecimal("39.90")))
                .thenReturn(Optional.of(json("{\"id\":\"invalido\"}")));

        assertThrows(IllegalStateException.class, () -> service.consultarCobrancaPix(10L, 99L));
        assertNull(pagamento.getMercadoPagoPagamentoId());
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verificarSemEnvioPix();
        verifyNoInteractions(assinaturaService);
    }

    @Test
    void consultaNaoRecuperaPixDeOutroPerfilComMesmoId() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        prepararTentativaIncerta(Assinatura.TipoConta.EMPRESA);

        assertThrows(IllegalArgumentException.class,
                () -> service.consultarCobrancaPix(Assinatura.TipoConta.ENTREGADOR, 10L, 99L));
        verifyNoInteractions(mercadoPagoService, assinaturaService);
    }

    @Test
    void listaSomentePixNaoResolvidosDaEmpresaSemConsultarProvedor() {
        prepararCriacaoPix(Assinatura.TipoConta.EMPRESA);
        PagamentoAssinatura incerto = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        incerto.setMercadoPagoPagamentoId(null);
        PagamentoAssinatura aprovado = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        aprovado.setId(98L);
        aprovado.setStatus(PagamentoAssinatura.Status.APROVADO);
        PagamentoAssinatura ativado = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        ativado.setId(97L);
        ativado.setStatus(PagamentoAssinatura.Status.APROVADO);
        ativado.setDataVencimento(LocalDateTime.now().plusDays(30));
        PagamentoAssinatura cancelado = pixParaCriacao(Assinatura.TipoConta.EMPRESA);
        cancelado.setId(96L);
        cancelado.setStatus(PagamentoAssinatura.Status.CANCELADO);
        PagamentoAssinatura cartao = pagamentoExistente();
        cartao.setId(95L);
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(incerto, aprovado, ativado, cancelado, cartao));

        List<Map<String, Object>> resultado = service.listarCobrancasPixPendentes(10L);

        assertEquals(List.of(99L, 98L), resultado.stream().map(item -> item.get("pagamentoId")).toList());
        assertEquals("AGUARDANDO_IDENTIFICACAO", resultado.get(0).get("situacaoRecuperacao"));
        assertEquals("AGUARDANDO_CONSULTA", resultado.get(1).get("situacaoRecuperacao"));
        assertFalse(resultado.get(0).containsKey("chaveIdempotencia"));
        verifyNoInteractions(mercadoPagoService, assinaturaService);
    }

    @Test
    void listaPixDoEntregadorSemConsultarEmpresaComMesmoId() {
        prepararCriacaoPix(Assinatura.TipoConta.ENTREGADOR);
        PagamentoAssinatura pagamento = pixParaCriacao(Assinatura.TipoConta.ENTREGADOR);
        when(pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(10L)).thenReturn(List.of(pagamento));

        List<Map<String, Object>> resultado = service.listarCobrancasPixPendentes(Assinatura.TipoConta.ENTREGADOR, 10L);

        assertEquals(1, resultado.size());
        assertEquals("ENTREGADOR", resultado.get(0).get("tipoConta"));
        assertEquals(new BigDecimal("9.90"), resultado.get(0).get("valor"));
        verify(pagamentoRepository, never()).findByEmpresaIdOrderByDataCriacaoDesc(anyLong());
        verifyNoInteractions(mercadoPagoService, assinaturaService);
    }

    private AtomicReference<PagamentoAssinatura> prepararRegistroNovaTentativa() {
        AtomicReference<PagamentoAssinatura> registro = new AtomicReference<>();
        when(pagamentoRepository.saveAndFlush(any(PagamentoAssinatura.class))).thenAnswer(invocacao -> {
            PagamentoAssinatura pagamento = invocacao.getArgument(0);
            if (pagamento.getId() == null) {
                pagamento.setId(99L);
            }
            registro.set(pagamento);
            return pagamento;
        });
        lenient().when(pagamentoRepository.buscarPorIdComBloqueio(99L))
                .thenAnswer(invocacao -> Optional.ofNullable(registro.get()));
        return registro;
    }

    private PagamentoAssinatura prepararTentativaIncerta(Assinatura.TipoConta tipoConta) {
        PagamentoAssinatura pagamento = pixParaCriacao(tipoConta);
        pagamento.setMercadoPagoPagamentoId(null);
        when(pagamentoRepository.buscarPorIdComBloqueio(99L)).thenReturn(Optional.of(pagamento));
        return pagamento;
    }

    private void verificarSemEnvioPix() {
        verify(mercadoPagoService, never()).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
    }

    private void verificarBloqueioRecorrente(Assinatura.TipoConta tipoConta, AssinaturaRecorrente.Status status) {
        prepararCriacaoPix(tipoConta);
        AssinaturaRecorrente registro = new AssinaturaRecorrente();
        registro.setStatus(status);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        List<AssinaturaRecorrente.Status> estados = List.of(AssinaturaRecorrente.Status.PENDENTE,
                AssinaturaRecorrente.Status.AUTORIZADA, AssinaturaRecorrente.Status.PAUSADA);
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            registro.setEmpresaId(10L);
            when(recorrenteRepository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(10L, estados))
                    .thenReturn(Optional.of(registro));
        } else {
            registro.setEntregadorId(10L);
            when(recorrenteRepository.findFirstByEntregadorIdAndStatusInOrderByIdDesc(10L, estados))
                    .thenReturn(Optional.of(registro));
        }

        IllegalStateException erro = assertThrows(IllegalStateException.class, () -> criarPix(tipoConta));

        assertTrue(erro.getMessage().contains("assinatura recorrente"));
        verificarSemNovaCobranca();
    }

    private void verificarChaveDeOutroPerfil(Assinatura.TipoConta solicitante, Assinatura.TipoConta titular) {
        prepararCriacaoPix(solicitante);
        PagamentoAssinatura pagamento = pixParaCriacao(titular);
        pagamento.setValor(solicitante == Assinatura.TipoConta.EMPRESA
                ? new BigDecimal("39.90") : new BigDecimal("9.90"));
        when(pagamentoRepository.findByChaveIdempotencia(CHAVE_PIX)).thenReturn(Optional.of(pagamento));

        IllegalArgumentException erro = assertThrows(IllegalArgumentException.class, () -> criarPix(solicitante));

        assertTrue(erro.getMessage().contains("chave de idempotência"));
        verificarSemNovaCobranca();
    }

    private void verificarSemNovaCobranca() {
        verifyNoInteractions(mercadoPagoService, assinaturaService);
        verify(pagamentoRepository, never()).saveAndFlush(any(PagamentoAssinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    private void prepararCriacaoPix(Assinatura.TipoConta tipoConta) {
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            Empresa empresa = new Empresa();
            empresa.setId(10L);
            empresa.setEmail("empresa@exemplo.com");
            when(entityManager.find(Empresa.class, 10L)).thenReturn(empresa);
            lenient().when(entityManager.find(Empresa.class, 10L, LockModeType.PESSIMISTIC_WRITE)).thenReturn(empresa);
        } else {
            Usuario entregador = new Usuario();
            entregador.setId(10L);
            entregador.setEmail("entregador@exemplo.com");
            when(entityManager.find(Usuario.class, 10L)).thenReturn(entregador);
            lenient().when(entityManager.find(Usuario.class, 10L, LockModeType.PESSIMISTIC_WRITE)).thenReturn(entregador);
        }
        @SuppressWarnings("unchecked")
        TypedQuery<Assinatura> consulta = mock(TypedQuery.class);
        lenient().when(entityManager.createQuery(anyString(), eq(Assinatura.class))).thenReturn(consulta);
        lenient().when(consulta.setParameter(anyString(), any())).thenReturn(consulta);
        lenient().when(consulta.setMaxResults(1)).thenReturn(consulta);
        lenient().when(consulta.getResultStream()).thenAnswer(invocacao -> Stream.empty());
    }

    private Map<String, Object> criarPix(Assinatura.TipoConta tipoConta) {
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            return service.criarCobrancaPix(10L, Assinatura.Plano.ESSENCIAL, CHAVE_PIX);
        }
        return service.criarCobrancaPix(tipoConta, 10L, Assinatura.Plano.ESSENCIAL, CHAVE_PIX);
    }

    private PagamentoAssinatura pixParaCriacao(Assinatura.TipoConta tipoConta) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setId(99L);
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            pagamento.setEmpresaId(10L);
            pagamento.setValor(new BigDecimal("39.90"));
        } else {
            pagamento.setEntregadorId(10L);
            pagamento.setValor(new BigDecimal("9.90"));
        }
        pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setChaveIdempotencia(CHAVE_PIX);
        pagamento.setMercadoPagoPagamentoId("12345");
        return pagamento;
    }

    private JsonNode respostaPix(String valor, String status) {
        return json("""
                {"id":"12345","external_reference":"entregueja-pagamento-99",
                "transaction_amount":%s,"currency_id":"BRL","payment_method_id":"pix","status":"%s"}
                """.formatted(valor, status));
    }
}
