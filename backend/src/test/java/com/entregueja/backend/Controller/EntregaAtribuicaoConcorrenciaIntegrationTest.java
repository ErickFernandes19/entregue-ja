package com.entregueja.backend.controller;

import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.EntregaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import com.entregueja.backend.service.FirebasePushService;
import com.entregueja.backend.service.JwtService;
import com.entregueja.backend.service.NotificacaoService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.test.web.servlet.result.MockMvcResultMatchers;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class EntregaAtribuicaoConcorrenciaIntegrationTest {

    @Container
    static final MySQLContainer<?> MYSQL =
            new MySQLContainer<>("mysql:8.4")
                    .withDatabaseName("entregueja_concorrencia_teste")
                    .withUsername("teste")
                    .withPassword("teste");

    @DynamicPropertySource
    static void propriedades(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
        registry.add("spring.jpa.show-sql", () -> "false");
        registry.add("jwt.secret",
                () -> "chave-de-testes-entregue-ja-com-mais-de-32-bytes");
        registry.add("google.routes.api-key", () -> "chave-teste");
        registry.add("cloudflare.r2.account-id", () -> "teste");
        registry.add("cloudflare.r2.access-key", () -> "teste");
        registry.add("cloudflare.r2.secret-key", () -> "teste");
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private EmpresaRepository empresaRepository;

    @Autowired
    private UsuarioRepository usuarioRepository;

    @Autowired
    private EntregaRepository entregaRepository;

    @Autowired
    private JwtService jwtService;

    @MockitoBean
    private NotificacaoService notificacaoService;

    @MockitoBean
    private FirebasePushService firebasePushService;

    private record DadosTeste(
            Long entregaId,
            Long entregadorAId,
            Long entregadorBId,
            String emailA,
            String emailB,
            String token
    ) {
    }

    private DadosTeste prepararDados() {
        String identificador = UUID.randomUUID().toString();

        Empresa empresa = new Empresa(
                "Empresa Teste",
                "empresa-" + identificador + "@teste.com",
                "senha-teste"
        );

        empresa = empresaRepository.saveAndFlush(empresa);

        Usuario entregadorA = new Usuario(
                null,
                "Entregador A",
                "entregador-a-" + identificador + "@teste.com",
                "senha-teste"
        );
        entregadorA.setEmpresa(empresa);
        entregadorA = usuarioRepository.saveAndFlush(entregadorA);

        Usuario entregadorB = new Usuario(
                null,
                "Entregador B",
                "entregador-b-" + identificador + "@teste.com",
                "senha-teste"
        );
        entregadorB.setEmpresa(empresa);
        entregadorB = usuarioRepository.saveAndFlush(entregadorB);

        Entrega entrega = new Entrega();
        entrega.setCliente("Cliente Teste");
        entrega.setEndereco("Rua Teste, 100");
        entrega.setStatus("PENDENTE");
        entrega.setEntregue(false);
        entrega.setEmpresa(empresa);
        entrega.setEntregador(null);

        entrega = entregaRepository.saveAndFlush(entrega);

        String token = jwtService.gerarToken(
                empresa.getId(),
                "EMPRESA"
        );

        return new DadosTeste(
                entrega.getId(),
                entregadorA.getId(),
                entregadorB.getId(),
                entregadorA.getEmail(),
                entregadorB.getEmail(),
                token
        );
    }

    private int atribuir(
            Long entregaId,
            String email,
            String token
    ) throws Exception {
        MvcResult resultado = mockMvc.perform(
                MockMvcRequestBuilders.put(
                                "/entregas/{id}/atribuir-entregador",
                                entregaId
                        )
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(
                                "{\"entregadorEmail\":\"" + email + "\"}"
                        )
        ).andReturn();

        return resultado.getResponse().getStatus();
    }

    @Test
    void empresaPodeAtribuirEntregador() throws Exception {
        DadosTeste dados = prepararDados();

        int status = atribuir(
                dados.entregaId(),
                dados.emailA(),
                dados.token()
        );

        assertEquals(200, status);

        Entrega entrega = entregaRepository
                .findById(dados.entregaId())
                .orElseThrow();

        assertNotNull(entrega.getEntregador());
        assertEquals(
                dados.entregadorAId(),
                entrega.getEntregador().getId()
        );
    }

    @Test
    void segundaAtribuicaoNaoSobrescrevePrimeira() throws Exception {
        DadosTeste dados = prepararDados();

        int primeiraResposta = atribuir(
                dados.entregaId(),
                dados.emailA(),
                dados.token()
        );

        int segundaResposta = atribuir(
                dados.entregaId(),
                dados.emailB(),
                dados.token()
        );

        assertEquals(200, primeiraResposta);
        assertEquals(400, segundaResposta);

        Entrega entrega = entregaRepository
                .findById(dados.entregaId())
                .orElseThrow();

        assertEquals(
                dados.entregadorAId(),
                entrega.getEntregador().getId()
        );
    }

    @Test
    void atribuicoesSimultaneasNaoSobrescrevemEntregador()
            throws Exception {

        DadosTeste dados = prepararDados();

        CountDownLatch inicio = new CountDownLatch(1);

        ExecutorService executor = Executors.newFixedThreadPool(2);

        try {
            Future<Integer> primeira = executor.submit(() -> {
                inicio.await();
                return atribuir(
                        dados.entregaId(),
                        dados.emailA(),
                        dados.token()
                );
            });

            Future<Integer> segunda = executor.submit(() -> {
                inicio.await();
                return atribuir(
                        dados.entregaId(),
                        dados.emailB(),
                        dados.token()
                );
            });

            inicio.countDown();

            int respostaA = primeira.get(30, TimeUnit.SECONDS);
            int respostaB = segunda.get(30, TimeUnit.SECONDS);

            assertTrue(
                    (respostaA == 200 && respostaB == 400)
                            || (respostaA == 400 && respostaB == 200),
                    "Esperado um HTTP 200 e um HTTP 400, mas recebidos: "
                            + respostaA + " e " + respostaB
            );

            Entrega entrega = entregaRepository
                    .findById(dados.entregaId())
                    .orElseThrow();

            assertNotNull(entrega.getEntregador());

            Long vencedorEsperado =
                    respostaA == 200
                            ? dados.entregadorAId()
                            : dados.entregadorBId();

            assertEquals(
                    vencedorEsperado,
                    entrega.getEntregador().getId()
            );

        } finally {
            inicio.countDown();
            executor.shutdownNow();
        }
    }
}
