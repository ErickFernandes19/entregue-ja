package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.PagamentoAssinatura;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
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
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class PagamentoAssinaturaJpaIntegrationTest {

    @Container
    static final MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_testes")
            .withUsername("testes")
            .withPassword("testes");

    @DynamicPropertySource
    static void configurarBanco(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.datasource.driver-class-name", mysql::getDriverClassName);
    }

    @Autowired
    private PagamentoAssinaturaRepository repository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Test
    void impedePagamentoExternoDuplicado() {
        String idExterno = "mp-" + UUID.randomUUID();
        repository.saveAndFlush(novoPagamento(idExterno, UUID.randomUUID().toString()));

        assertThrows(DataIntegrityViolationException.class, () ->
                repository.saveAndFlush(novoPagamento(idExterno, UUID.randomUUID().toString())));
    }

    @Test
    void impedeChaveIdempotenciaDuplicada() {
        String chave = UUID.randomUUID().toString();
        repository.saveAndFlush(novoPagamento("mp-" + UUID.randomUUID(), chave));

        assertThrows(DataIntegrityViolationException.class, () ->
                repository.saveAndFlush(novoPagamento("mp-" + UUID.randomUUID(), chave)));
    }

    @Test
    void rollbackNaoPersisteAtualizacao() {
        PagamentoAssinatura pagamento = repository.saveAndFlush(
                novoPagamento("mp-" + UUID.randomUUID(), UUID.randomUUID().toString()));
        Long id = pagamento.getId();
        TransactionTemplate transacao = novaTransacao();

        assertThrows(IllegalStateException.class, () -> transacao.execute(status -> {
            PagamentoAssinatura bloqueado = repository.buscarPorIdComBloqueio(id).orElseThrow();
            bloqueado.setStatus(PagamentoAssinatura.Status.APROVADO);
            repository.saveAndFlush(bloqueado);
            throw new IllegalStateException("Rollback simulado");
        }));

        assertEquals(PagamentoAssinatura.Status.PENDENTE, repository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void bloqueioPessimistaSerializaAtualizacoes() throws Exception {
        PagamentoAssinatura pagamento = repository.saveAndFlush(
                novoPagamento("mp-" + UUID.randomUUID(), UUID.randomUUID().toString()));
        Long id = pagamento.getId();
        CountDownLatch primeiroBloqueou = new CountDownLatch(1);
        CountDownLatch liberarPrimeiro = new CountDownLatch(1);
        CountDownLatch segundoIniciou = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        try {
            Future<?> primeiro = executor.submit(() -> novaTransacao().execute(status -> {
                PagamentoAssinatura bloqueado = repository.buscarPorIdComBloqueio(id).orElseThrow();
                primeiroBloqueou.countDown();
                try {
                    if (!liberarPrimeiro.await(15, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Tempo esgotado aguardando liberação");
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException(e);
                }
                bloqueado.setStatus(PagamentoAssinatura.Status.APROVADO);
                repository.saveAndFlush(bloqueado);
                return null;
            }));

            assertTrue(primeiroBloqueou.await(15, TimeUnit.SECONDS));

            Future<PagamentoAssinatura.Status> segundo = executor.submit(() -> {
                segundoIniciou.countDown();
                return novaTransacao().execute(status ->
                        repository.buscarPorIdComBloqueio(id).orElseThrow().getStatus());
            });

            assertTrue(segundoIniciou.await(5, TimeUnit.SECONDS));
            assertThrows(java.util.concurrent.TimeoutException.class,
                    () -> segundo.get(300, TimeUnit.MILLISECONDS));
            liberarPrimeiro.countDown();
            primeiro.get(15, TimeUnit.SECONDS);
            assertEquals(PagamentoAssinatura.Status.APROVADO, segundo.get(15, TimeUnit.SECONDS));
        } finally {
            liberarPrimeiro.countDown();
            executor.shutdownNow();
        }
    }

    private TransactionTemplate novaTransacao() {
        TransactionTemplate transacao = new TransactionTemplate(transactionManager);
        transacao.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return transacao;
    }

    private PagamentoAssinatura novoPagamento(String idExterno, String chave) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(10L);
        pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setStatus(PagamentoAssinatura.Status.PENDENTE);
        pagamento.setValor(new BigDecimal("39.90"));
        pagamento.setMercadoPagoPagamentoId(idExterno);
        pagamento.setMercadoPagoAssinaturaId("assinatura-teste");
        pagamento.setChaveIdempotencia(chave);
        return pagamento;
    }
}
