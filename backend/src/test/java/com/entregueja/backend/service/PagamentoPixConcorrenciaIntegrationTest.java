package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@DataJpaTest(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.jpa.show-sql=false"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import({PagamentoAssinaturaService.class, AssinaturaService.class})
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class PagamentoPixConcorrenciaIntegrationTest {

    private static final BigDecimal VALOR = new BigDecimal("39.90");

    @Container
    static final MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_pix_integracao")
            .withUsername("teste")
            .withPassword("teste");

    @DynamicPropertySource
    static void configurarBanco(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
    }

    @Autowired private PagamentoAssinaturaService service;
    @Autowired private PagamentoAssinaturaRepository pagamentoRepository;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private AssinaturaRepository assinaturaRepository;
    @MockitoBean private MercadoPagoService mercadoPagoService;

    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void tentativaConfirmadaAntesDoEnvioSobreviveFalhaESemReenvio() {
        Long empresaId = criarEmpresa();
        String chave = chave();
        when(mercadoPagoService.criarPagamentoPix(eq(VALOR), anyString(), anyString(), anyString(), eq(chave)))
                .thenAnswer(invocacao -> {
                    assertFalse(TransactionSynchronizationManager.isActualTransactionActive());
                    PagamentoAssinatura persistido = pagamentoRepository.findByChaveIdempotencia(chave).orElseThrow();
                    assertEquals(empresaId, persistido.getEmpresaId());
                    assertEquals(PagamentoAssinatura.Status.PENDENTE, persistido.getStatus());
                    assertNull(persistido.getMercadoPagoPagamentoId());
                    assertEquals(referencia(persistido.getId()), invocacao.getArgument(3));
                    throw new MercadoPagoService.MercadoPagoException("Falha simulada", null);
                });

        assertThrows(MercadoPagoService.MercadoPagoException.class, () -> criarPix(empresaId, chave));
        PagamentoAssinatura persistido = pagamentoRepository.findByChaveIdempotencia(chave).orElseThrow();
        assertNull(persistido.getMercadoPagoPagamentoId());
        when(mercadoPagoService.buscarPagamentoPixPorReferencia(referencia(persistido.getId()), VALOR))
                .thenReturn(Optional.empty());

        Map<String, Object> recuperacao = criarPix(empresaId, chave);
        assertEquals(persistido.getId(), recuperacao.get("pagamentoId"));
        assertEquals("PENDENTE", recuperacao.get("status"));
        assertEquals(true, recuperacao.get("buscaReferenciaRealizada"));
        assertEquals(true, recuperacao.get("requerConciliacao"));
        assertThrows(IllegalStateException.class, () -> criarPix(empresaId, chave()));
        assertEquals(1, pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(empresaId).size());
        verify(mercadoPagoService, times(1)).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void solicitacoesSimultaneasComChaveIgualOuDiferenteNaoCriamOutroPix() throws Exception {
        Long empresaId = criarEmpresa();
        String chave = chave();
        CountDownLatch envioIniciado = new CountDownLatch(1);
        CountDownLatch liberarResposta = new CountDownLatch(1);
        when(mercadoPagoService.criarPagamentoPix(eq(VALOR), anyString(), anyString(), anyString(), eq(chave)))
                .thenAnswer(invocacao -> {
                    String referencia = invocacao.getArgument(3);
                    envioIniciado.countDown();
                    assertTrue(liberarResposta.await(30, TimeUnit.SECONDS));
                    return resposta(referencia, "pending", "39.90");
                });
        when(mercadoPagoService.buscarPagamentoPixPorReferencia(anyString(), eq(VALOR)))
                .thenReturn(Optional.empty());

        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Map<String, Object>> primeira = executor.submit(() -> criarPix(empresaId, chave));
            assertTrue(envioIniciado.await(10, TimeUnit.SECONDS));
            Future<Map<String, Object>> segunda = executor.submit(() -> criarPix(empresaId, chave));
            Map<String, Object> existente = segunda.get(10, TimeUnit.SECONDS);
            assertEquals("PENDENTE", existente.get("status"));
            assertNull(existente.get("mercadoPagoPagamentoId"));
            Future<?> terceira = executor.submit(() -> assertThrows(IllegalStateException.class,
                    () -> criarPix(empresaId, chave())));
            terceira.get(10, TimeUnit.SECONDS);
            liberarResposta.countDown();
            Map<String, Object> resultado = primeira.get(30, TimeUnit.SECONDS);
            assertEquals(existente.get("pagamentoId"), resultado.get("pagamentoId"));
            assertNotNull(resultado.get("mercadoPagoPagamentoId"));
        } finally {
            liberarResposta.countDown();
            executor.shutdownNow();
            assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS));
        }
        assertEquals(1, pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(empresaId).size());
        verify(mercadoPagoService, times(1)).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void recuperacaoAprovadaSimultaneaAtivaPlanoUmaUnicaVez() throws Exception {
        Long empresaId = criarEmpresa();
        PagamentoAssinatura pagamento = registrarTentativa(empresaId, chave());
        Assinatura assinatura = new Assinatura();
        assinatura.setTipoConta(Assinatura.TipoConta.EMPRESA);
        assinatura.setContaId(empresaId);
        assinatura.setPlano(Assinatura.Plano.ESSENCIAL);
        assinatura.setStatus(Assinatura.Status.ATIVA);
        assinatura.setTesteGratuito(false);
        assinatura.setRenovacaoAutomatica(false);
        assinatura.setDataInicio(LocalDateTime.now().minusDays(5));
        assinatura.setDataVencimento(LocalDateTime.now().plusDays(15).withNano(0));
        assinatura = assinaturaRepository.saveAndFlush(assinatura);
        Long assinaturaId = assinatura.getId();
        LocalDateTime vencimentoAnterior = assinatura.getDataVencimento();
        String referencia = referencia(pagamento.getId());
        JsonNode resposta = resposta(referencia, "approved", "39.90");
        when(mercadoPagoService.buscarPagamentoPixPorReferencia(referencia, VALOR)).thenReturn(Optional.of(resposta));
        when(mercadoPagoService.consultarPagamento(resposta.path("id").asText())).thenReturn(resposta);

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch inicio = new CountDownLatch(1);
        try {
            Future<Map<String, Object>> primeira = executor.submit(() -> {
                assertTrue(inicio.await(10, TimeUnit.SECONDS));
                return service.consultarCobrancaPix(empresaId, pagamento.getId());
            });
            Future<Map<String, Object>> segunda = executor.submit(() -> {
                assertTrue(inicio.await(10, TimeUnit.SECONDS));
                return service.consultarCobrancaPix(empresaId, pagamento.getId());
            });
            inicio.countDown();
            assertEquals(true, primeira.get(30, TimeUnit.SECONDS).get("planoAtivado"));
            assertEquals(true, segunda.get(30, TimeUnit.SECONDS).get("planoAtivado"));
        } finally {
            inicio.countDown();
            executor.shutdownNow();
            assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS));
        }
        PagamentoAssinatura confirmado = pagamentoRepository.findById(pagamento.getId()).orElseThrow();
        Assinatura atual = assinaturaRepository.findById(assinaturaId).orElseThrow();
        assertEquals(PagamentoAssinatura.Status.APROVADO, confirmado.getStatus());
        assertEquals(resposta.path("id").asText(), confirmado.getMercadoPagoPagamentoId());
        assertEquals(vencimentoAnterior.plusDays(30), atual.getDataVencimento());
        assertEquals(atual.getDataVencimento(), confirmado.getDataVencimento());
        assertFalse(atual.isRenovacaoAutomatica());
        verify(mercadoPagoService, times(1)).buscarPagamentoPixPorReferencia(referencia, VALOR);
        verify(mercadoPagoService, never()).criarPagamentoPix(any(), anyString(), anyString(), anyString(), anyString());
    }

    @Test
    void respostaInconsistenteNaoVinculaIdentificadorNemAtivaPlano() {
        Long empresaId = criarEmpresa();
        String chave = chave();
        when(mercadoPagoService.criarPagamentoPix(eq(VALOR), anyString(), anyString(), anyString(), eq(chave)))
                .thenAnswer(invocacao -> resposta(invocacao.getArgument(3), "approved", "79.90"));

        assertThrows(IllegalStateException.class, () -> criarPix(empresaId, chave));
        PagamentoAssinatura persistido = pagamentoRepository.findByChaveIdempotencia(chave).orElseThrow();
        assertEquals(PagamentoAssinatura.Status.PENDENTE, persistido.getStatus());
        assertNull(persistido.getMercadoPagoPagamentoId());
        assertNull(persistido.getDataVencimento());
        assertTrue(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, empresaId, Assinatura.Status.ATIVA).isEmpty());
    }

    @Test
    void outraEmpresaNaoPodeConsultarNemReutilizarTentativa() {
        Long titular = criarEmpresa();
        Long outra = criarEmpresa();
        PagamentoAssinatura pagamento = registrarTentativa(titular, chave());

        assertThrows(IllegalArgumentException.class, () -> service.consultarCobrancaPix(outra, pagamento.getId()));
        assertThrows(IllegalArgumentException.class, () -> criarPix(outra, pagamento.getChaveIdempotencia()));
        assertTrue(service.listarCobrancasPixPendentes(outra).isEmpty());
        assertEquals(1, service.listarCobrancasPixPendentes(titular).size());
        verifyNoInteractions(mercadoPagoService);
    }

    private Long criarEmpresa() {
        return empresaRepository.saveAndFlush(new Empresa(
                "Empresa teste", "pix-" + UUID.randomUUID() + "@example.com", "senha-teste")).getId();
    }

    private String chave() {
        return UUID.randomUUID().toString();
    }

    private Map<String, Object> criarPix(Long empresaId, String chave) {
        return service.criarCobrancaPix(empresaId, Assinatura.Plano.ESSENCIAL, chave);
    }

    private PagamentoAssinatura registrarTentativa(Long empresaId, String chave) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(empresaId);
        pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setValor(VALOR);
        pagamento.setChaveIdempotencia(chave);
        return pagamentoRepository.saveAndFlush(pagamento);
    }

    private String referencia(Long id) {
        return "entregueja-pagamento-" + id;
    }

    private JsonNode resposta(String referencia, String status, String valor) {
        String id = "900000" + referencia.substring("entregueja-pagamento-".length());
        return mapper.createObjectNode()
                .put("id", id)
                .put("external_reference", referencia)
                .put("transaction_amount", new BigDecimal(valor))
                .put("currency_id", "BRL")
                .put("payment_method_id", "pix")
                .put("status", status);
    }
}
