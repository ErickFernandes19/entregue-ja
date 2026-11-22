package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import({PagamentoAssinaturaService.class, AssinaturaService.class})
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class PagamentoWebhookConcorrenciaIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_webhooks_teste")
            .withUsername("teste")
            .withPassword("teste");

    @DynamicPropertySource
    static void propriedades(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
        registry.add("spring.jpa.show-sql", () -> "false");
    }

    @Autowired
    private PagamentoAssinaturaService pagamentoService;

    @Autowired
    private EmpresaRepository empresaRepository;

    @Autowired
    private AssinaturaRecorrenteRepository recorrenteRepository;

    @Autowired
    private PagamentoAssinaturaRepository pagamentoRepository;

    @Autowired
    private AssinaturaRepository assinaturaRepository;

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @MockitoBean
    private MercadoPagoService mercadoPagoService;

    private final ObjectMapper mapper = new ObjectMapper();
    private String pagamentoExterno;
    private Long empresaId;
    private Long recorrenteId;
    private String assinaturaExterna;

    @BeforeEach
    void preparar() throws Exception {
        TransactionTemplate transacao = new TransactionTemplate(transactionManager);
        String identificador = UUID.randomUUID().toString();
        pagamentoExterno = Long.toUnsignedString(UUID.randomUUID().getMostSignificantBits());
        Long[] ids = transacao.execute(status -> {
            Empresa empresa = new Empresa("Empresa Teste", "teste-" + identificador + "@example.com", "senha-teste");
            empresa = empresaRepository.saveAndFlush(empresa);

            AssinaturaRecorrente recorrente = new AssinaturaRecorrente();
            recorrente.setEmpresaId(empresa.getId());
            recorrente.setPlano(Assinatura.Plano.ESSENCIAL);
            recorrente.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
            recorrente.setValor(new BigDecimal("39.90"));
            recorrente.setChaveIdempotencia(UUID.randomUUID().toString());
            recorrente.setMercadoPagoAssinaturaId("assinatura_" + UUID.randomUUID().toString().replace("-", ""));
            recorrente = recorrenteRepository.saveAndFlush(recorrente);
            return new Long[]{empresa.getId(), recorrente.getId()};
        });

        assertNotNull(ids);
        empresaId = ids[0];
        recorrenteId = ids[1];
        assinaturaExterna = recorrenteRepository.findById(recorrenteId).orElseThrow().getMercadoPagoAssinaturaId();

        JsonNode pagamento = mapper.readTree("""
                {
                  "id": "%s",
                  "preapproval_id": "%s",
                  "transaction_amount": 39.90,
                  "currency_id": "BRL",
                  "payment_type_id": "credit_card",
                  "status": "approved"
                }
                """.formatted(pagamentoExterno, assinaturaExterna));

        JsonNode assinatura = mapper.readTree("""
                {
                  "id": "%s",
                  "external_reference": "entregueja-recorrente-%d",
                  "auto_recurring": {
                    "transaction_amount": 39.90,
                    "currency_id": "BRL"
                  }
                }
                """.formatted(assinaturaExterna, recorrenteId));

        when(mercadoPagoService.consultarPagamentoRecorrente(anyString())).thenReturn(pagamento);
        when(mercadoPagoService.consultarAssinaturaRecorrente(anyString())).thenReturn(assinatura);
    }

    @Test
    void webhookRepetidoNaoRenovaDuasVezes() {
        Map<String, Object> primeira = pagamentoService.processarPagamentoRecorrente(pagamentoExterno);
        PagamentoAssinatura pagamento = pagamentoRepository.findByMercadoPagoPagamentoId(pagamentoExterno).orElseThrow();
        LocalDateTime vencimentoInicial = pagamento.getDataVencimento();

        Map<String, Object> segunda = pagamentoService.processarPagamentoRecorrente(pagamentoExterno);
        PagamentoAssinatura atualizado = pagamentoRepository.findByMercadoPagoPagamentoId(pagamentoExterno).orElseThrow();

        assertNotNull(vencimentoInicial);
        assertEquals(vencimentoInicial, atualizado.getDataVencimento());
        assertEquals(primeira.get("pagamentoId"), segunda.get("pagamentoId"));
        assertEquals(1L, contarPagamentos());
        assertEquals(1L, contarAssinaturasAtivas());
    }

    @Test
    void webhooksSimultaneosCriamUmPagamentoEUmaAssinatura() throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch inicio = new CountDownLatch(1);
        try {
            Callable<Map<String, Object>> tarefa = () -> {
                assertTrue(inicio.await(15, TimeUnit.SECONDS));
                return pagamentoService.processarPagamentoRecorrente(pagamentoExterno);
            };
            List<Future<Map<String, Object>>> resultados = new ArrayList<>();
            resultados.add(executor.submit(tarefa));
            resultados.add(executor.submit(tarefa));
            inicio.countDown();

            Map<String, Object> primeiro = resultados.get(0).get(45, TimeUnit.SECONDS);
            Map<String, Object> segundo = resultados.get(1).get(45, TimeUnit.SECONDS);

            assertEquals(primeiro.get("pagamentoId"), segundo.get("pagamentoId"));
            assertEquals(Boolean.TRUE, primeiro.get("planoAtivado"));
            assertEquals(Boolean.TRUE, segundo.get("planoAtivado"));
            assertEquals(1L, contarPagamentos());
            assertEquals(1L, contarAssinaturasAtivas());

            PagamentoAssinatura pagamento = pagamentoRepository.findByMercadoPagoPagamentoId(pagamentoExterno).orElseThrow();
            assertEquals(PagamentoAssinatura.Status.APROVADO, pagamento.getStatus());
            assertNotNull(pagamento.getDataVencimento());
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void pagamentoComValorInvalidoNaoPersisteNemAtivaPlano() throws Exception {
        JsonNode invalido = mapper.readTree("""
                {
                  "id": "%s",
                  "preapproval_id": "%s",
                  "transaction_amount": 79.90,
                  "currency_id": "BRL",
                  "payment_type_id": "credit_card",
                  "status": "approved"
                }
                """.formatted(pagamentoExterno, assinaturaExterna));
        when(mercadoPagoService.consultarPagamentoRecorrente(anyString())).thenReturn(invalido);

        assertThrows(IllegalStateException.class,
                () -> pagamentoService.processarPagamentoRecorrente(pagamentoExterno));
        assertEquals(0L, contarPagamentos());
        assertEquals(0L, contarAssinaturasAtivas());
    }

    private long contarPagamentos() {
        return entityManager.createQuery(
                        "select count(p) from PagamentoAssinatura p where p.empresaId = :empresaId", Long.class)
                .setParameter("empresaId", empresaId)
                .getSingleResult();
    }

    private long contarAssinaturasAtivas() {
        return entityManager.createQuery(
                        "select count(a) from Assinatura a where a.tipoConta = :tipo and a.contaId = :empresaId and a.status = :status",
                        Long.class)
                .setParameter("tipo", Assinatura.TipoConta.EMPRESA)
                .setParameter("empresaId", empresaId)
                .setParameter("status", Assinatura.Status.ATIVA)
                .getSingleResult();
    }
}
