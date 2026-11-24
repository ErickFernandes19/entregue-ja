package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
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
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.jpa.show-sql=false"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import(AssinaturaService.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class PagamentoRecorrenteConcorrenciaIntegrationTest {

    @Container
    static final MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_teste_concorrencia")
            .withUsername("teste")
            .withPassword("teste");

    @DynamicPropertySource
    static void configurarBanco(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
    }

    @Autowired private AssinaturaService assinaturaService;
    @Autowired private EmpresaRepository empresaRepository;
    @Autowired private AssinaturaRepository assinaturaRepository;
    @Autowired private AssinaturaRecorrenteRepository recorrenteRepository;
    @Autowired private PagamentoAssinaturaRepository pagamentoRepository;
    @Autowired private PlatformTransactionManager transactionManager;

    @Test
    void doisProcessamentosSimultaneosNaoRenovamDuasVezes() throws Exception {
        TransactionTemplate transacao = new TransactionTemplate(transactionManager);
        Long[] ids = transacao.execute(status -> {
            Empresa empresa = empresaRepository.saveAndFlush(new Empresa(
                    "Empresa teste", "teste-" + UUID.randomUUID() + "@example.com", "senha-teste"));
            String assinaturaExterna = "assinatura_teste_" + UUID.randomUUID();
            AssinaturaRecorrente recorrente = new AssinaturaRecorrente();
            recorrente.setEmpresaId(empresa.getId());
            recorrente.setPlano(Assinatura.Plano.ESSENCIAL);
            recorrente.setValor(new BigDecimal("39.90"));
            recorrente.setEmailPagador(empresa.getEmail());
            recorrente.setMercadoPagoAssinaturaId(assinaturaExterna);
            recorrente.setChaveIdempotencia(UUID.randomUUID().toString());
            recorrente.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
            recorrente.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
            recorrenteRepository.saveAndFlush(recorrente);

            Assinatura assinatura = new Assinatura();
            assinatura.setTipoConta(Assinatura.TipoConta.EMPRESA);
            assinatura.setContaId(empresa.getId());
            assinatura.setPlano(Assinatura.Plano.ESSENCIAL);
            assinatura.setStatus(Assinatura.Status.ATIVA);
            assinatura.setTesteGratuito(false);
            assinatura.setDataInicio(LocalDateTime.now().minusDays(2));
            assinatura.setDataVencimento(LocalDateTime.now().plusDays(15));
            assinatura.setRenovacaoAutomatica(true);
            assinatura.setMercadoPagoAssinaturaId(assinaturaExterna);
            assinaturaRepository.saveAndFlush(assinatura);
            PagamentoAssinatura pagamento = new PagamentoAssinatura();
            pagamento.setEmpresaId(empresa.getId());
            pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
            pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
            pagamento.setStatus(PagamentoAssinatura.Status.APROVADO);
            pagamento.setValor(new BigDecimal("39.90"));
            pagamento.setMercadoPagoPagamentoId("123456789" + Math.abs(UUID.randomUUID().getMostSignificantBits() % 100000000));
            pagamento.setMercadoPagoAssinaturaId(assinatura.getMercadoPagoAssinaturaId());
            pagamento.setChaveIdempotencia(UUID.randomUUID().toString());
            pagamento.setDataAprovacao(LocalDateTime.now());
            pagamentoRepository.saveAndFlush(pagamento);
            return new Long[]{empresa.getId(), pagamento.getId(), assinatura.getId()};
        });
        assertNotNull(ids);
        LocalDateTime vencimentoAnterior = transacao.execute(status -> assinaturaRepository.findById(ids[2])
                .orElseThrow().getDataVencimento());
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch inicio = new CountDownLatch(1);
        try {
            List<Future<Assinatura>> resultados = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                resultados.add(executor.submit(() -> {
                    assertTrue(inicio.await(10, TimeUnit.SECONDS));
                    return assinaturaService.ativarPlanoPagoPorCartao(ids[0], ids[1]);
                }));
            }
            inicio.countDown();
            for (Future<Assinatura> resultado : resultados) {
                assertNotNull(resultado.get(30, TimeUnit.SECONDS));
            }
        } finally {
            executor.shutdownNow();
        }
        transacao.executeWithoutResult(status -> {
            Assinatura assinatura = assinaturaRepository.findById(ids[2]).orElseThrow();
            PagamentoAssinatura pagamento = pagamentoRepository.findById(ids[1]).orElseThrow();
            AssinaturaRecorrente recorrente = recorrenteRepository
                    .findByMercadoPagoAssinaturaId(pagamento.getMercadoPagoAssinaturaId()).orElseThrow();
            assertEquals(vencimentoAnterior.plusDays(30), assinatura.getDataVencimento());
            assertEquals(assinatura.getDataVencimento(), pagamento.getDataVencimento());
            assertEquals(Assinatura.Status.ATIVA, assinatura.getStatus());
            assertTrue(assinatura.isRenovacaoAutomatica());
            assertEquals(AssinaturaRecorrente.Status.AUTORIZADA, recorrente.getStatus());
            assertEquals(assinatura.getMercadoPagoAssinaturaId(), recorrente.getMercadoPagoAssinaturaId());
            assertEquals(ids[0], recorrente.getEmpresaId());
            assertNull(recorrente.getEntregadorId());
        });
    }
}
