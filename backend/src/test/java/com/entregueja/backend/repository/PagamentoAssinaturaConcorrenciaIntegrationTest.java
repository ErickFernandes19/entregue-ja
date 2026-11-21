package com.entregueja.backend.repository;

import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

@Testcontainers
class PagamentoAssinaturaConcorrenciaIntegrationTest {

    @Container
    static final MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_teste")
            .withUsername("teste")
            .withPassword("teste");

    private Connection conectar() throws SQLException {
        return DriverManager.getConnection(mysql.getJdbcUrl(), mysql.getUsername(), mysql.getPassword());
    }

    private void prepararTabela() throws SQLException {
        try (Connection conexao = conectar(); Statement comando = conexao.createStatement()) {
            comando.execute("CREATE TABLE IF NOT EXISTS pagamentos_assinatura_teste ("
                    + "id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, "
                    + "empresa_id BIGINT NOT NULL, "
                    + "valor DECIMAL(10,2) NOT NULL, "
                    + "status VARCHAR(20) NOT NULL, "
                    + "mercado_pago_pagamento_id VARCHAR(100) UNIQUE, "
                    + "chave_idempotencia VARCHAR(100) NOT NULL, "
                    + "CONSTRAINT uk_pagamento_idempotencia_teste UNIQUE (chave_idempotencia)"
                    + ") ENGINE=InnoDB");
        }
    }

    private long inserir(Connection conexao, String pagamentoExterno, String chave) throws SQLException {
        try (PreparedStatement comando = conexao.prepareStatement(
                "INSERT INTO pagamentos_assinatura_teste "
                        + "(empresa_id, valor, status, mercado_pago_pagamento_id, chave_idempotencia) "
                        + "VALUES (?, ?, ?, ?, ?)", Statement.RETURN_GENERATED_KEYS)) {
            comando.setLong(1, 10L);
            comando.setBigDecimal(2, new BigDecimal("39.90"));
            comando.setString(3, "PENDENTE");
            comando.setString(4, pagamentoExterno);
            comando.setString(5, chave);
            comando.executeUpdate();
            try (ResultSet ids = comando.getGeneratedKeys()) {
                assertTrue(ids.next());
                return ids.getLong(1);
            }
        }
    }

    private int contar(String pagamentoExterno) throws SQLException {
        try (Connection conexao = conectar(); PreparedStatement comando = conexao.prepareStatement(
                "SELECT COUNT(*) FROM pagamentos_assinatura_teste WHERE mercado_pago_pagamento_id = ?")) {
            comando.setString(1, pagamentoExterno);
            try (ResultSet resultado = comando.executeQuery()) {
                assertTrue(resultado.next());
                return resultado.getInt(1);
            }
        }
    }

    @Test
    void naoPermiteDoisRegistrosComMesmoPagamentoExterno() throws Exception {
        prepararTabela();
        String pagamento = "mp-" + UUID.randomUUID();
        try (Connection conexao = conectar()) {
            inserir(conexao, pagamento, UUID.randomUUID().toString());
            assertThrows(SQLException.class,
                    () -> inserir(conexao, pagamento, UUID.randomUUID().toString()));
        }
        assertEquals(1, contar(pagamento));
    }

    @Test
    void naoPermiteDuasCobrancasComMesmaChaveIdempotencia() throws Exception {
        prepararTabela();
        String chave = UUID.randomUUID().toString();
        String primeiro = "mp-" + UUID.randomUUID();
        String segundo = "mp-" + UUID.randomUUID();
        try (Connection conexao = conectar()) {
            inserir(conexao, primeiro, chave);
            assertThrows(SQLException.class, () -> inserir(conexao, segundo, chave));
        }
        assertEquals(1, contar(primeiro));
        assertEquals(0, contar(segundo));
    }

    @Test
    void bloqueioPessimistaImpedeAtualizacaoConcorrente() throws Exception {
        prepararTabela();
        String pagamento = "mp-" + UUID.randomUUID();
        long id;
        try (Connection conexao = conectar()) {
            id = inserir(conexao, pagamento, UUID.randomUUID().toString());
        }
        try (Connection primeira = conectar()) {
            primeira.setAutoCommit(false);
            try {
                try (PreparedStatement bloqueio = primeira.prepareStatement(
                        "SELECT id FROM pagamentos_assinatura_teste WHERE id = ? FOR UPDATE")) {
                    bloqueio.setLong(1, id);
                    try (ResultSet resultado = bloqueio.executeQuery()) {
                        assertTrue(resultado.next());
                    }
                }
                CompletableFuture<Boolean> concorrente = CompletableFuture.supplyAsync(() -> {
                    try (Connection segunda = conectar(); Statement configuracao = segunda.createStatement()) {
                        configuracao.execute("SET innodb_lock_wait_timeout = 1");
                        try (PreparedStatement atualizacao = segunda.prepareStatement(
                                "UPDATE pagamentos_assinatura_teste SET status = 'APROVADO' WHERE id = ?")) {
                            atualizacao.setLong(1, id);
                            atualizacao.executeUpdate();
                            return false;
                        } catch (SQLException esperado) {
                            return esperado.getErrorCode() == 1205;
                        }
                    } catch (SQLException erro) {
                        throw new IllegalStateException(erro);
                    }
                });
                assertTrue(concorrente.get(15, TimeUnit.SECONDS));
            } finally {
                primeira.rollback();
                primeira.setAutoCommit(true);
            }
        }
        try (Connection conexao = conectar(); PreparedStatement consulta = conexao.prepareStatement(
                "SELECT status FROM pagamentos_assinatura_teste WHERE id = ?")) {
            consulta.setLong(1, id);
            try (ResultSet resultado = consulta.executeQuery()) {
                assertTrue(resultado.next());
                assertEquals("PENDENTE", resultado.getString(1));
            }
        }
    }

    @Test
    void rollbackNaoPersistePagamentoIncompleto() throws Exception {
        prepararTabela();
        String pagamento = "mp-" + UUID.randomUUID();
        try (Connection conexao = conectar()) {
            conexao.setAutoCommit(false);
            try {
                inserir(conexao, pagamento, UUID.randomUUID().toString());
            } finally {
                conexao.rollback();
            }
        }
        assertEquals(0, contar(pagamento));
    }
}
