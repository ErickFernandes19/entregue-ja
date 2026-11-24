package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.AssinaturaRecorrenteRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.persistence.TypedQuery;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AssinaturaRecorrenteServiceTest {

    @Mock
    private AssinaturaRecorrenteRepository repository;
    @Mock
    private MercadoPagoService mercadoPagoService;
    @Mock
    private PagamentoAssinaturaRepository pagamentoRepository;
    @Mock
    private PagamentoAssinaturaService pagamentoService;
    @Mock
    private EntityManager entityManager;

    private AssinaturaRecorrenteService service;
    private final ObjectMapper mapper = new ObjectMapper();
    private final String chave = UUID.randomUUID().toString();

    @BeforeEach
    void preparar() {
        service = new AssinaturaRecorrenteService(
                repository, mercadoPagoService, pagamentoRepository,
                pagamentoService, entityManager, "https://exemplo.com/retorno"
        );
        Empresa empresa = new Empresa();
        empresa.setId(10L);
        empresa.setEmail("empresa@exemplo.com");
        lenient().when(entityManager.find(Empresa.class, 10L, LockModeType.PESSIMISTIC_WRITE))
                .thenReturn(empresa);
    }

    private AssinaturaRecorrente registro(String email) {
        AssinaturaRecorrente registro = new AssinaturaRecorrente();
        registro.setId(55L);
        registro.setEmpresaId(10L);
        registro.setPlano(Assinatura.Plano.ESSENCIAL);
        registro.setValor(new BigDecimal("39.90"));
        registro.setEmailPagador(email);
        registro.setChaveIdempotencia(chave);
        registro.setStatus(AssinaturaRecorrente.Status.PENDENTE);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.PREPARADA);
        return registro;
    }

    private void prepararCriacao() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(AssinaturaRecorrente.class))).thenAnswer(invocacao -> {
            AssinaturaRecorrente salvo = invocacao.getArgument(0);
            salvo.setId(55L);
            return salvo;
        });
        lenient().when(repository.save(any(AssinaturaRecorrente.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));
    }

    @Test
    void criaAssinaturaComEmailDoPagadorEDonoEmpresa() throws Exception {
        prepararCriacao();
        when(mercadoPagoService.criarAssinaturaRecorrente(
                anyString(), eq("pagador@exemplo.com"),
                eq("entregueja-recorrente-55"), eq(new BigDecimal("39.90")), anyString()
        )).thenReturn(mapper.readTree("""
                {"id":"sub55","external_reference":"entregueja-recorrente-55",
                "init_point":"https://exemplo.com/autorizacao","status":"pending"}
                """));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, " pagador@exemplo.com "
        );

        assertEquals(55L, resultado.get("assinaturaId"));
        assertEquals("sub55", resultado.get("mercadoPagoAssinaturaId"));
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        var captor = org.mockito.ArgumentCaptor.forClass(AssinaturaRecorrente.class);
        verify(repository).saveAndFlush(captor.capture());
        assertEquals(10L, captor.getValue().getEmpresaId());
        assertEquals("pagador@exemplo.com", captor.getValue().getEmailPagador());
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(
                anyString(), eq("pagador@exemplo.com"), anyString(), any(), anyString()
        );
    }

    @Test
    void mesmaChaveMesmosDadosRecuperaAssinaturaSemNovaCobranca() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "PAGADOR@EXEMPLO.COM"
        );

        assertEquals(55L, resultado.get("assinaturaId"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void mesmaChaveComOutroEmailEhRejeitada() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "outro@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void mesmaChaveDeOutraEmpresaEhRejeitada() {
        AssinaturaRecorrente existente = registro("pagador@exemplo.com");
        existente.setEmpresaId(20L);
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(existente));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void registroAntigoSemEmailEhRejeitado() {
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro(null)));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void emailInvalidoEhRejeitadoAntesDeCriarAssinatura() {
        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "invalido"
        ));
        verifyNoInteractions(repository, mercadoPagoService);
    }

    @Test
    void falhaDeComunicacaoMarcaTentativaComoIncerta() {
        prepararCriacao();
        when(mercadoPagoService.criarAssinaturaRecorrente(
                anyString(), anyString(), anyString(), any(), anyString()
        )).thenThrow(new IllegalStateException("Falha de comunicação"));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));

        var captor = org.mockito.ArgumentCaptor.forClass(AssinaturaRecorrente.class);
        verify(repository, atLeastOnce()).save(captor.capture());
        assertEquals(AssinaturaRecorrente.EstadoCriacao.INCERTA,
                captor.getAllValues().get(captor.getAllValues().size() - 1).getEstadoCriacao());
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(
                anyString(), anyString(), anyString(), any(), anyString()
        );
    }

    @Test
    void tentativaIncertaExistenteBloqueiaNovaChave() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        AssinaturaRecorrente incerta = registro("pagador@exemplo.com");
        incerta.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.of(incerta));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void mesmaChaveIncertaNaoReenviaAoMercadoPago() {
        AssinaturaRecorrente incerta = registro("pagador@exemplo.com");
        incerta.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.INCERTA);
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(incerta));

        Map<String, Object> resultado = service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        );

        assertEquals("INCERTA", resultado.get("estadoCriacao"));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void erroNaGravacaoInicialNaoChamaMercadoPago() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.findFirstByEmpresaIdAndEstadoCriacaoInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(AssinaturaRecorrente.class)))
                .thenThrow(new IllegalStateException("Falha no banco"));

        assertThrows(IllegalStateException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"
        ));
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void pixPendenteDaEmpresaBloqueiaAssinaturaRecorrente() {
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(pix(Assinatura.TipoConta.EMPRESA, PagamentoAssinatura.Status.PENDENTE)));

        verificarBloqueioPix(Assinatura.TipoConta.EMPRESA);
    }

    @Test
    void pixAprovadoSemAtivacaoDaEmpresaBloqueiaAssinaturaRecorrente() {
        when(pagamentoRepository.findByEmpresaIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(pix(Assinatura.TipoConta.EMPRESA, PagamentoAssinatura.Status.APROVADO)));

        verificarBloqueioPix(Assinatura.TipoConta.EMPRESA);
    }

    @Test
    void pixPendenteDoEntregadorBloqueiaAssinaturaRecorrente() {
        prepararEntregador();
        when(pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(pix(Assinatura.TipoConta.ENTREGADOR, PagamentoAssinatura.Status.PENDENTE)));

        verificarBloqueioPix(Assinatura.TipoConta.ENTREGADOR);
    }

    @Test
    void pixAprovadoSemAtivacaoDoEntregadorBloqueiaAssinaturaRecorrente() {
        prepararEntregador();
        when(pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(pix(Assinatura.TipoConta.ENTREGADOR, PagamentoAssinatura.Status.APROVADO)));

        verificarBloqueioPix(Assinatura.TipoConta.ENTREGADOR);
    }

    @Test
    void criaAssinaturaEssencialDoEntregadorComPrecoCorreto() throws Exception {
        verificarCriacaoEntregador(Assinatura.Plano.ESSENCIAL, "9.90");
    }

    @Test
    void criaAssinaturaProfissionalDoEntregadorComPrecoCorreto() throws Exception {
        verificarCriacaoEntregador(Assinatura.Plano.PROFISSIONAL, "19.90");
    }

    @Test
    void pixJaAtivadoNaoBloqueiaNovaAssinaturaRecorrenteDoEntregador() throws Exception {
        PagamentoAssinatura pagamento = pix(Assinatura.TipoConta.ENTREGADOR, PagamentoAssinatura.Status.APROVADO);
        pagamento.setDataVencimento(LocalDateTime.now().plusDays(30));
        when(pagamentoRepository.findByEntregadorIdOrderByDataCriacaoDesc(10L))
                .thenReturn(List.of(pagamento));

        verificarCriacaoEntregador(Assinatura.Plano.ESSENCIAL, "9.90");
    }

    @Test
    void empresaNaoPodeReutilizarChaveDeEntregadorComMesmoId() {
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(registroEntregador()));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void entregadorNaoPodeReutilizarChaveDeEmpresaComMesmoId() {
        prepararEntregador();
        when(repository.findByChaveIdempotencia(chave))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        assertThrows(IllegalArgumentException.class, () -> service.criar(
                Assinatura.TipoConta.ENTREGADOR, 10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void entregadorRecuperaMesmaChaveSemNovaCobranca() {
        prepararEntregador();
        when(repository.findByChaveIdempotencia(chave)).thenReturn(Optional.of(registroEntregador()));

        Map<String, Object> resultado = service.criar(Assinatura.TipoConta.ENTREGADOR, 10L,
                Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com");

        assertEquals(55L, resultado.get("assinaturaId"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void assinaturaAutorizadaDoEntregadorBloqueiaNovaChave() {
        prepararEntregador();
        AssinaturaRecorrente existente = registroEntregador();
        existente.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
        existente.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        when(repository.findFirstByEntregadorIdAndStatusInOrderByIdDesc(eq(10L), anyList()))
                .thenReturn(Optional.of(existente));

        assertThrows(IllegalStateException.class, () -> service.criar(Assinatura.TipoConta.ENTREGADOR,
                10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void entregadorConsultaPropriaAssinatura() throws Exception {
        prepararEntregador();
        AssinaturaRecorrente registro = registroEntregador();
        registro.setMercadoPagoAssinaturaId("sub55");
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(registro));
        when(mercadoPagoService.consultarAssinaturaRecorrente("sub55"))
                .thenReturn(mapper.readTree("""
                        {"id":"sub55","external_reference":"entregueja-recorrente-55","status":"authorized"}
                        """));
        when(repository.save(registro)).thenReturn(registro);

        Map<String, Object> resultado = service.consultar(Assinatura.TipoConta.ENTREGADOR, 10L, 55L);

        assertEquals("AUTORIZADA", resultado.get("status"));
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        assertEquals(false, resultado.get("planoAtivado"));
        verify(repository).save(registro);
        verifyNoInteractions(pagamentoService);
    }

    @Test
    void entregadorCancelaPropriaAssinatura() throws Exception {
        prepararEntregador();
        AssinaturaRecorrente registro = registroEntregador();
        registro.setMercadoPagoAssinaturaId("sub55");
        registro.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
        registro.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(registro));
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(mapper.readTree("""
                        {"id":"sub55","external_reference":"entregueja-recorrente-55","status":"cancelled"}
                        """));
        when(repository.save(registro)).thenReturn(registro);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.ENTREGADOR, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.ENTREGADOR, "sub55", List.of(ativa));

        Map<String, Object> resultado = service.cancelar(Assinatura.TipoConta.ENTREGADOR, 10L, 55L);

        assertEquals("CANCELADA", resultado.get("status"));
        assertNotNull(registro.getDataCancelamento());
        verificarPlanoPreservado(ativa, vencimento);
        verify(repository).save(registro);
    }

    @Test
    void entregadorNaoConsultaNemCancelaAssinaturaDeEmpresaComMesmoId() {
        prepararEntregador();
        when(repository.buscarPorIdComBloqueio(55L))
                .thenReturn(Optional.of(registro("pagador@exemplo.com")));

        assertThrows(IllegalArgumentException.class,
                () -> service.consultar(Assinatura.TipoConta.ENTREGADOR, 10L, 55L));
        assertThrows(IllegalArgumentException.class,
                () -> service.cancelar(Assinatura.TipoConta.ENTREGADOR, 10L, 55L));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).save(any());
    }

    @Test
    void empresaNaoConsultaNemCancelaAssinaturaDeEntregadorComMesmoId() {
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(registroEntregador()));

        assertThrows(IllegalArgumentException.class, () -> service.consultar(10L, 55L));
        assertThrows(IllegalArgumentException.class, () -> service.cancelar(10L, 55L));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).save(any());
    }

    @Test
    void empresaCancelaRenovacaoSemPerderPlanoPagoNemTrocaAgendada() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.EMPRESA, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        LocalDateTime inicio = ativa.getDataInicio();
        ativa.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        ativa.setDataTrocaAgendada(vencimento);
        prepararConsultaRenovacao(Assinatura.TipoConta.EMPRESA, "sub55", List.of(ativa));
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(repository.save(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "cancelled"));

        Map<String, Object> resultado = service.cancelar(10L, 55L);

        assertEquals("CANCELADA", resultado.get("status"));
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        verificarPlanoPreservado(ativa, vencimento);
        assertEquals(inicio, ativa.getDataInicio());
        assertEquals(Assinatura.Plano.PROFISSIONAL, ativa.getPlanoAgendado());
        assertEquals(vencimento, ativa.getDataTrocaAgendada());
    }

    @Test
    void webhookDeCancelamentoDesativaRenovacaoDoEntregador() throws Exception {
        prepararEntregador();
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.ENTREGADOR);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.ENTREGADOR, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.ENTREGADOR, "sub55", List.of(ativa));
        when(repository.findByMercadoPagoAssinaturaId("sub55")).thenReturn(Optional.of(recorrente));
        when(repository.saveAndFlush(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.consultarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "cancelled"));

        Map<String, Object> resultado = service.sincronizarNotificacao("sub55");

        assertEquals("CANCELADA", resultado.get("status"));
        verificarPlanoPreservado(ativa, vencimento);
        verify(entityManager).refresh(recorrente, LockModeType.PESSIMISTIC_WRITE);
        verify(mercadoPagoService, never()).cancelarAssinaturaRecorrente(anyString());
    }

    @Test
    void consultaDeRecorrenciaEncerradaPreservaPlanoPago() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.EMPRESA, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.EMPRESA, "sub55", List.of(ativa));
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(repository.save(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.consultarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "finished"));

        assertEquals("ENCERRADA", service.consultar(10L, 55L).get("status"));
        verificarPlanoPreservado(ativa, vencimento);
    }

    @Test
    void cancelamentoRepetidoNaoEnviaNovaSolicitacaoNemAlteraVencimento() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.EMPRESA, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.EMPRESA, "sub55", List.of(ativa));
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(repository.save(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "cancelled"));

        service.cancelar(10L, 55L);
        LocalDateTime cancelamento = recorrente.getDataCancelamento();
        assertNotNull(cancelamento);
        assertEquals("CANCELADA", service.cancelar(10L, 55L).get("status"));

        assertEquals(cancelamento, recorrente.getDataCancelamento());
        verificarPlanoPreservado(ativa, vencimento);
        verify(mercadoPagoService, times(1)).cancelarAssinaturaRecorrente("sub55");
        verify(repository, times(1)).save(recorrente);
    }

    @Test
    void cancelamentoAntigoCorrigeRenovacaoLocalSemChamarMercadoPago() {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        recorrente.setStatus(AssinaturaRecorrente.Status.CANCELADA);
        recorrente.setDataCancelamento(LocalDateTime.now().minusDays(1));
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.EMPRESA, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.EMPRESA, "sub55", List.of(ativa));
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));

        assertEquals("CANCELADA", service.cancelar(10L, 55L).get("status"));
        verificarPlanoPreservado(ativa, vencimento);
        verifyNoInteractions(mercadoPagoService);
    }

    @Test
    void cancelamentoDeRecorrenciaAntigaConsultaSomenteVinculoAntigo() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        prepararConsultaRenovacao(Assinatura.TipoConta.EMPRESA, "sub55", List.of());
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(repository.save(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "cancelled"));

        assertEquals("CANCELADA", service.cancelar(10L, 55L).get("status"));
        verify(entityManager, times(1)).createQuery(eq(CONSULTA_RENOVACAO), eq(Assinatura.class));
    }

    @Test
    void cancelamentoNaoConfirmadoPreservaRenovacao() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "authorized"));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.cancelar(10L, 55L));

        assertEquals("O Mercado Pago ainda não confirmou o cancelamento.", erro.getMessage());
        assertEquals(AssinaturaRecorrente.Status.AUTORIZADA, recorrente.getStatus());
        assertNull(recorrente.getDataCancelamento());
        verify(entityManager, never()).createQuery(anyString(), eq(Assinatura.class));
        verify(repository, never()).save(any());
    }

    @Test
    void cancelamentoComIdentificadorExternoDivergenteNaoAlteraPlano() throws Exception {
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.EMPRESA);
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(mercadoPagoService.cancelarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub99", "cancelled"));

        assertThrows(IllegalStateException.class, () -> service.cancelar(10L, 55L));

        assertEquals(AssinaturaRecorrente.Status.AUTORIZADA, recorrente.getStatus());
        verify(entityManager, never()).createQuery(anyString(), eq(Assinatura.class));
        verify(repository, never()).save(any());
    }

    @Test
    void conciliacaoSincronizaCancelamentoDoEntregador() throws Exception {
        prepararEntregador();
        when(entityManager.find(Usuario.class, 10L)).thenReturn(new Usuario());
        AssinaturaRecorrente recorrente = recorrenteAutorizada(Assinatura.TipoConta.ENTREGADOR);
        Assinatura ativa = planoAtivo(Assinatura.TipoConta.ENTREGADOR, "sub55");
        LocalDateTime vencimento = ativa.getDataVencimento();
        prepararConsultaRenovacao(Assinatura.TipoConta.ENTREGADOR, "sub55", List.of(ativa));
        when(repository.findByEntregadorIdOrderByIdDesc(10L)).thenReturn(List.of(recorrente));
        when(repository.buscarPorIdComBloqueio(55L)).thenReturn(Optional.of(recorrente));
        when(repository.save(recorrente)).thenReturn(recorrente);
        when(mercadoPagoService.consultarAssinaturaRecorrente("sub55"))
                .thenReturn(respostaExterna("sub55", "cancelled"));
        when(pagamentoService.recuperarMensalidadesRecorrentes(Assinatura.TipoConta.ENTREGADOR, 10L))
                .thenReturn(Map.of());

        Map<String, Object> resultado = service.conciliarPagamentos(Assinatura.TipoConta.ENTREGADOR, 10L);

        assertEquals(0, resultado.get("falhas"));
        assertEquals(1, resultado.get("recorrentesSincronizadas"));
        assertEquals(AssinaturaRecorrente.Status.CANCELADA, recorrente.getStatus());
        verificarPlanoPreservado(ativa, vencimento);
    }

    private static final String CONSULTA_RENOVACAO =
            "select a from Assinatura a where a.tipoConta = :tipo and a.contaId = :contaId "
                    + "and a.status = :status and a.mercadoPagoAssinaturaId = :assinaturaExterna";

    @SuppressWarnings("unchecked")
    private void prepararConsultaRenovacao(Assinatura.TipoConta tipoConta, String idExterno,
                                           List<Assinatura> assinaturas) {
        TypedQuery<Assinatura> consulta = mock(TypedQuery.class);
        when(entityManager.createQuery(CONSULTA_RENOVACAO, Assinatura.class)).thenReturn(consulta);
        when(consulta.setParameter("tipo", tipoConta)).thenReturn(consulta);
        when(consulta.setParameter("contaId", 10L)).thenReturn(consulta);
        when(consulta.setParameter("status", Assinatura.Status.ATIVA)).thenReturn(consulta);
        when(consulta.setParameter("assinaturaExterna", idExterno)).thenReturn(consulta);
        when(consulta.getResultList()).thenReturn(assinaturas);
    }

    private AssinaturaRecorrente recorrenteAutorizada(Assinatura.TipoConta tipoConta) {
        AssinaturaRecorrente recorrente = tipoConta == Assinatura.TipoConta.EMPRESA
                ? registro("pagador@exemplo.com") : registroEntregador();
        recorrente.setMercadoPagoAssinaturaId("sub55");
        recorrente.setStatus(AssinaturaRecorrente.Status.AUTORIZADA);
        recorrente.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        return recorrente;
    }

    private Assinatura planoAtivo(Assinatura.TipoConta tipoConta, String idExterno) {
        Assinatura assinatura = new Assinatura();
        assinatura.setTipoConta(tipoConta);
        assinatura.setContaId(10L);
        assinatura.setPlano(Assinatura.Plano.ESSENCIAL);
        assinatura.setStatus(Assinatura.Status.ATIVA);
        assinatura.setTesteGratuito(false);
        assinatura.setDataInicio(LocalDateTime.now().minusDays(5));
        assinatura.setDataVencimento(LocalDateTime.now().plusDays(25));
        assinatura.setRenovacaoAutomatica(true);
        assinatura.setMercadoPagoAssinaturaId(idExterno);
        return assinatura;
    }

    private void verificarPlanoPreservado(Assinatura assinatura, LocalDateTime vencimento) {
        assertFalse(assinatura.isRenovacaoAutomatica());
        assertEquals(Assinatura.Status.ATIVA, assinatura.getStatus());
        assertEquals(Assinatura.Plano.ESSENCIAL, assinatura.getPlano());
        assertEquals(vencimento, assinatura.getDataVencimento());
        assertEquals("sub55", assinatura.getMercadoPagoAssinaturaId());
    }

    private com.fasterxml.jackson.databind.JsonNode respostaExterna(String id, String status) {
        return mapper.createObjectNode()
                .put("id", id)
                .put("external_reference", "entregueja-recorrente-55")
                .put("status", status);
    }

    private void prepararEntregador() {
        Usuario entregador = mock(Usuario.class);
        when(entregador.getEmail()).thenReturn("entregador@exemplo.com");
        when(entityManager.find(Usuario.class, 10L, LockModeType.PESSIMISTIC_WRITE)).thenReturn(entregador);
    }

    private AssinaturaRecorrente registroEntregador() {
        AssinaturaRecorrente registro = registro("pagador@exemplo.com");
        registro.setEmpresaId(null);
        registro.setEntregadorId(10L);
        registro.setValor(new BigDecimal("9.90"));
        return registro;
    }

    private PagamentoAssinatura pix(Assinatura.TipoConta tipoConta, PagamentoAssinatura.Status status) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            pagamento.setEmpresaId(10L);
        } else {
            pagamento.setEntregadorId(10L);
        }
        pagamento.setPlano(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(status);
        pagamento.setValor(new BigDecimal(tipoConta == Assinatura.TipoConta.EMPRESA ? "39.90" : "9.90"));
        return pagamento;
    }

    private void verificarBloqueioPix(Assinatura.TipoConta tipoConta) {
        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.criar(tipoConta, 10L, Assinatura.Plano.ESSENCIAL, chave, "pagador@exemplo.com"));
        assertTrue(erro.getMessage().contains("Pix não resolvida"));
        verifyNoInteractions(mercadoPagoService);
        verify(repository, never()).saveAndFlush(any());
    }

    private void verificarCriacaoEntregador(Assinatura.Plano plano, String preco) throws Exception {
        prepararEntregador();
        BigDecimal valor = new BigDecimal(preco);
        when(repository.saveAndFlush(any(AssinaturaRecorrente.class))).thenAnswer(invocacao -> {
            AssinaturaRecorrente salvo = invocacao.getArgument(0);
            salvo.setId(55L);
            return salvo;
        });
        when(repository.save(any(AssinaturaRecorrente.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));
        when(mercadoPagoService.criarAssinaturaRecorrente(anyString(), eq("pagador@exemplo.com"),
                eq("entregueja-recorrente-55"), eq(valor), anyString()))
                .thenReturn(mapper.readTree("""
                        {"id":"sub55","external_reference":"entregueja-recorrente-55",
                        "init_point":"https://exemplo.com/autorizacao","status":"pending"}
                        """));

        Map<String, Object> resultado = service.criar(Assinatura.TipoConta.ENTREGADOR, 10L,
                plano, chave, "pagador@exemplo.com");

        assertEquals(55L, resultado.get("assinaturaId"));
        assertEquals(valor, resultado.get("valorMensal"));
        assertEquals("CONFIRMADA", resultado.get("estadoCriacao"));
        assertEquals(false, resultado.get("planoAtivado"));
        var captor = org.mockito.ArgumentCaptor.forClass(AssinaturaRecorrente.class);
        verify(repository).saveAndFlush(captor.capture());
        assertNull(captor.getValue().getEmpresaId());
        assertEquals(10L, captor.getValue().getEntregadorId());
        assertEquals(plano, captor.getValue().getPlano());
        assertEquals(valor, captor.getValue().getValor());
        verify(mercadoPagoService, times(1)).criarAssinaturaRecorrente(anyString(),
                eq("pagador@exemplo.com"), eq("entregueja-recorrente-55"), eq(valor), anyString());
        verify(pagamentoRepository, never()).findByEmpresaIdOrderByDataCriacaoDesc(anyLong());
    }
}
