package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.EmpresaRepository;
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
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@DataJpaTest(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.jpa.show-sql=false",
        "mercadopago.subscription-return-url=https://example.com/retorno"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import(AssinaturaRecorrenteService.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class AssinaturaRecorrenteCriacaoIntegrationTest {

    @Container
    static final MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_recorrente_integracao")
            .withUsername("teste")
            .withPassword("teste");

    @DynamicPropertySource
    static void configurarBanco(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
    }

    @Autowired private AssinaturaRecorrenteService service;
    @Autowired private AssinaturaRecorrenteRepository repository;
    @Autowired private EmpresaRepository empresaRepository;

    @MockitoBean private MercadoPagoService mercadoPagoService;
    @MockitoBean private PagamentoAssinaturaService pagamentoService;

    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void confirmaPreparacaoAntesDeEnviarAoMercadoPago() throws Exception {
        Long empresaId = criarEmpresa();
        String chave = UUID.randomUUID().toString();
        AtomicInteger chamadas = new AtomicInteger();
        when(mercadoPagoService.criarAssinaturaRecorrente(anyString(), anyString(), anyString(), any(BigDecimal.class), anyString()))
                .thenAnswer(invocacao -> {
                    chamadas.incrementAndGet();
                    String referencia = invocacao.getArgument(2);
                    Long registroId = Long.parseLong(referencia.substring("entregueja-recorrente-".length()));
                    AssinaturaRecorrente persistida = repository.findById(registroId).orElseThrow();
                    assertEquals(AssinaturaRecorrente.EstadoCriacao.ENVIANDO, persistida.getEstadoCriacao());
                    assertEquals(chave, persistida.getChaveIdempotencia());
                    assertNull(persistida.getMercadoPagoAssinaturaId());
                    return respostaMercadoPago("sub-" + registroId, referencia);
                });

        Map<String, Object> resultado = service.criar(empresaId, Assinatura.Plano.ESSENCIAL, chave, "pagador@example.com");

        assertEquals(1, chamadas.get());
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        AssinaturaRecorrente persistida = repository.findByChaveIdempotencia(chave).orElseThrow();
        assertEquals(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA, persistida.getEstadoCriacao());
        assertEquals("sub-" + persistida.getId(), persistida.getMercadoPagoAssinaturaId());
    }

    @Test
    void falhaExternaMantemTentativaIncertaSemReenvio() {
        Long empresaId = criarEmpresa();
        String chave = UUID.randomUUID().toString();
        when(mercadoPagoService.criarAssinaturaRecorrente(anyString(), anyString(), anyString(), any(BigDecimal.class), anyString()))
                .thenThrow(new IllegalStateException("Falha de rede simulada"));

        assertThrows(IllegalStateException.class,
                () -> service.criar(empresaId, Assinatura.Plano.ESSENCIAL, chave, "pagador@example.com"));

        AssinaturaRecorrente persistida = repository.findByChaveIdempotencia(chave).orElseThrow();
        assertEquals(AssinaturaRecorrente.EstadoCriacao.INCERTA, persistida.getEstadoCriacao());
        assertNull(persistida.getMercadoPagoAssinaturaId());

        Map<String, Object> repeticao = service.criar(empresaId, Assinatura.Plano.ESSENCIAL, chave, "pagador@example.com");
        assertEquals("INCERTA", repeticao.get("estadoCriacao"));
        assertThrows(IllegalStateException.class,
                () -> service.criar(empresaId, Assinatura.Plano.ESSENCIAL,
                        UUID.randomUUID().toString(), "pagador@example.com"));
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(
                anyString(), anyString(), anyString(), any(BigDecimal.class), anyString());
    }

    @Test
    void duasSolicitacoesSimultaneasComMesmaChaveEnviamUmaVez() throws Exception {
        Long empresaId = criarEmpresa();
        String chave = UUID.randomUUID().toString();
        CountDownLatch chamadaExterna = new CountDownLatch(1);
        CountDownLatch liberarResposta = new CountDownLatch(1);
        AtomicInteger chamadas = new AtomicInteger();
        when(mercadoPagoService.criarAssinaturaRecorrente(anyString(), anyString(), anyString(), any(BigDecimal.class), anyString()))
                .thenAnswer(invocacao -> {
                    chamadas.incrementAndGet();
                    chamadaExterna.countDown();
                    if (!liberarResposta.await(15, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Tempo esgotado na simulação");
                    }
                    String referencia = invocacao.getArgument(2);
                    return respostaMercadoPago("sub-" + UUID.randomUUID(), referencia);
                });

        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Map<String, Object>> primeira = executor.submit(
                    () -> service.criar(empresaId, Assinatura.Plano.ESSENCIAL, chave, "pagador@example.com"));
            assertTrue(chamadaExterna.await(15, TimeUnit.SECONDS));
            Future<Map<String, Object>> segunda = executor.submit(
                    () -> service.criar(empresaId, Assinatura.Plano.ESSENCIAL, chave, "pagador@example.com"));
            Map<String, Object> segundaResposta = segunda.get(20, TimeUnit.SECONDS);
            assertEquals("ENVIANDO", segundaResposta.get("estadoCriacao"));
            liberarResposta.countDown();
            Map<String, Object> primeiraResposta = primeira.get(20, TimeUnit.SECONDS);
            assertEquals("CONFIRMADA", primeiraResposta.get("estadoCriacao"));
            assertEquals(primeiraResposta.get("assinaturaId"), segundaResposta.get("assinaturaId"));
            assertEquals(1, chamadas.get());
            List<AssinaturaRecorrente> registros = repository.findByEmpresaIdOrderByIdDesc(empresaId);
            assertEquals(1, registros.size());
        } finally {
            liberarResposta.countDown();
            executor.shutdownNow();
        }
    }

    @Test
    void chaveDiferenteEhBloqueadaEnquantoCriacaoEstaIncerta() {
        Long empresaId = criarEmpresa();
        AssinaturaRecorrente tentativa = new AssinaturaRecorrente();
        tentativa.setEmpresaId(empresaId);
        tentativa.setPlano(Assinatura.Plano.ESSENCIAL);
        tentativa.setValor(new BigDecimal("39.90"));
        tentativa.setEmailPagador("pagador@example.com");
        tentativa.setChaveIdempotencia(UUID.randomUUID().toString());
        tentativa.setStatus(AssinaturaRecorrente.Status.PENDENTE);
        tentativa.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        repository.saveAndFlush(tentativa);

        assertThrows(IllegalStateException.class,
                () -> service.criar(empresaId, Assinatura.Plano.ESSENCIAL,
                        UUID.randomUUID().toString(), "pagador@example.com"));
        verifyNoInteractions(mercadoPagoService);
        assertEquals(1, repository.findByEmpresaIdOrderByIdDesc(empresaId).size());
    }

    private Long criarEmpresa() {
        Empresa empresa = empresaRepository.saveAndFlush(new Empresa(
                "Empresa integração", "integracao-" + UUID.randomUUID() + "@example.com", "senha-teste"));
        return empresa.getId();
    }

    private com.fasterxml.jackson.databind.JsonNode respostaMercadoPago(String id, String referencia) {
        return mapper.createObjectNode()
                .put("id", id)
                .put("external_reference", referencia)
                .put("init_point", "https://example.com/autorizar")
                .put("status", "pending");
    }
}
