package com.entregueja.backend.service;

import com.entregueja.backend.entity.DispositivoFcm;
import com.entregueja.backend.repository.DispositivoFcmRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import(NotificacaoService.class)
class NotificacaoDispositivoIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("entregueja_dispositivos_teste")
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
    private NotificacaoService notificacaoService;

    @Autowired
    private DispositivoFcmRepository dispositivoRepository;

    private String tokenUnico() {
        return "fcm_teste_" + UUID.randomUUID();
    }

    private String hash(String token) throws Exception {
        byte[] resumo = MessageDigest.getInstance("SHA-256")
                .digest(token.getBytes(StandardCharsets.UTF_8));
        return HexFormat.of().formatHex(resumo);
    }

    @Test
    void registrarDispositivoPersisteHashSha256() throws Exception {
        String token = tokenUnico();

        notificacaoService.registrarDispositivo("EMPRESA", 101L, token, "ANDROID");
        dispositivoRepository.flush();

        DispositivoFcm dispositivo = dispositivoRepository.findByTokenHash(hash(token)).orElseThrow();
        assertEquals(token, dispositivo.getToken());
        assertEquals(hash(token), dispositivo.getTokenHash());
        assertEquals("EMPRESA", dispositivo.getTipoConta());
        assertEquals(101L, dispositivo.getContaId());
        assertEquals("ANDROID", dispositivo.getPlataforma());
        assertNotNull(dispositivo.getCriadoEm());
    }

    @Test
    void registrarMesmoTokenNaoDuplicaDispositivo() throws Exception {
        String token = tokenUnico();

        notificacaoService.registrarDispositivo("EMPRESA", 102L, token, "ANDROID");
        dispositivoRepository.flush();
        Long primeiroId = dispositivoRepository.findByTokenHash(hash(token)).orElseThrow().getId();

        notificacaoService.registrarDispositivo("EMPRESA", 102L, token, "ANDROID");
        dispositivoRepository.flush();

        DispositivoFcm dispositivo = dispositivoRepository.findByTokenHash(hash(token)).orElseThrow();
        assertEquals(primeiroId, dispositivo.getId());
        assertEquals(1L, dispositivoRepository.findByTipoContaAndContaId("EMPRESA", 102L).size());
    }

    @Test
    void registrarTokenEmOutraContaAtualizaVinculo() throws Exception {
        String token = tokenUnico();

        notificacaoService.registrarDispositivo("EMPRESA", 103L, token, "ANDROID");
        dispositivoRepository.flush();
        Long primeiroId = dispositivoRepository.findByTokenHash(hash(token)).orElseThrow().getId();

        notificacaoService.registrarDispositivo("ENTREGADOR", 203L, token, "WEB");
        dispositivoRepository.flush();

        DispositivoFcm dispositivo = dispositivoRepository.findByTokenHash(hash(token)).orElseThrow();
        assertEquals(primeiroId, dispositivo.getId());
        assertEquals("ENTREGADOR", dispositivo.getTipoConta());
        assertEquals(203L, dispositivo.getContaId());
        assertEquals("WEB", dispositivo.getPlataforma());
        assertTrue(notificacaoService.listarTokens("EMPRESA", 103L).isEmpty());
        assertEquals(List.of(token), notificacaoService.listarTokens("ENTREGADOR", 203L));
    }

    @Test
    void outraContaNaoPodeRemoverDispositivo() throws Exception {
        String token = tokenUnico();

        notificacaoService.registrarDispositivo("EMPRESA", 104L, token, "ANDROID");
        dispositivoRepository.flush();

        assertFalse(notificacaoService.removerDispositivo("EMPRESA", 999L, token));
        assertFalse(notificacaoService.removerDispositivo("ENTREGADOR", 104L, token));
        assertTrue(dispositivoRepository.findByTokenHash(hash(token)).isPresent());

        assertTrue(notificacaoService.removerDispositivo("EMPRESA", 104L, token));
        dispositivoRepository.flush();
        assertTrue(dispositivoRepository.findByTokenHash(hash(token)).isEmpty());
    }
}
