package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.AssinaturaRecorrente;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.persistence.TypedQuery;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AssinaturaServiceTest {

    @Mock
    private AssinaturaRepository assinaturaRepository;
    @Mock
    private UsuarioRepository usuarioRepository;
    @Mock
    private EmpresaRepository empresaRepository;
    @Mock
    private PagamentoAssinaturaRepository pagamentoRepository;
    @Mock
    private EntityManager entityManager;
    @Mock
    private TypedQuery<AssinaturaRecorrente> consultaRecorrencia;
    @InjectMocks
    private AssinaturaService service;

    private static final Long EMPRESA_ID = 10L;

    @BeforeEach
    void preparar() {
        lenient().when(entityManager.find(
                        eq(Empresa.class),
                        eq(EMPRESA_ID),
                        eq(LockModeType.PESSIMISTIC_WRITE)))
                .thenReturn(new Empresa());
    }

    @Test
    void agendarUpgradePreservaPlanoEVencimento() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        LocalDateTime vencimento = atual.getDataVencimento();

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));
        when(assinaturaRepository.save(atual)).thenReturn(atual);

        Assinatura resultado = service.agendarTrocaPlano(
                EMPRESA_ID,
                Assinatura.Plano.PROFISSIONAL);

        assertEquals(Assinatura.Plano.ESSENCIAL, resultado.getPlano());
        assertEquals(Assinatura.Plano.PROFISSIONAL, resultado.getPlanoAgendado());
        assertEquals(vencimento, resultado.getDataVencimento());
        assertEquals(vencimento, resultado.getDataTrocaAgendada());
        verify(assinaturaRepository).save(atual);
    }

    @Test
    void agendarDowngradePreservaPlanoEVencimento() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.PROFISSIONAL);

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));
        when(assinaturaRepository.save(atual)).thenReturn(atual);

        service.agendarTrocaPlano(EMPRESA_ID, Assinatura.Plano.ESSENCIAL);

        assertEquals(Assinatura.Plano.PROFISSIONAL, atual.getPlano());
        assertEquals(Assinatura.Plano.ESSENCIAL, atual.getPlanoAgendado());
        assertEquals(
                atual.getDataVencimento(),
                atual.getDataTrocaAgendada());
    }

    @Test
    void naoPermiteAgendarMesmoPlano() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        assertThrows(IllegalArgumentException.class,
                () -> service.agendarTrocaPlano(
                        EMPRESA_ID,
                        Assinatura.Plano.ESSENCIAL));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void cancelarTrocaMantemPlanoAtual() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        atual.setDataTrocaAgendada(atual.getDataVencimento());

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));
        when(assinaturaRepository.save(atual)).thenReturn(atual);

        service.cancelarTrocaAgendada(EMPRESA_ID);

        assertEquals(Assinatura.Plano.ESSENCIAL, atual.getPlano());
        assertNull(atual.getPlanoAgendado());
        assertNull(atual.getDataTrocaAgendada());
    }

    @Test
    void pagamentoNaoAprovadoNaoAtivaPlano() {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(EMPRESA_ID);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setStatus(PagamentoAssinatura.Status.RECUSADO);

        when(pagamentoRepository.buscarPorIdComBloqueio(20L))
                .thenReturn(Optional.of(pagamento));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 20L));
        assertEquals("O pagamento ainda não foi confirmado.", erro.getMessage());

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pagamentoAprovadoNaoPodeSerAplicadoAntesDaTroca() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        atual.setDataTrocaAgendada(atual.getDataVencimento());

        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(EMPRESA_ID);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setStatus(PagamentoAssinatura.Status.APROVADO);
        pagamento.setDataAprovacao(LocalDateTime.now());
        pagamento.setMercadoPagoPagamentoId("12345");
        pagamento.setMercadoPagoAssinaturaId("assinatura_123");
        pagamento.setPlano(Assinatura.Plano.PROFISSIONAL);
        pagamento.setValor(new BigDecimal("79.90"));

        when(pagamentoRepository.buscarPorIdComBloqueio(21L))
                .thenReturn(Optional.of(pagamento));

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 21L));
        assertEquals("Existe uma troca programada. Aguarde o vencimento antes de ativar uma nova mensalidade.",
                erro.getMessage());

        assertEquals(Assinatura.Plano.ESSENCIAL, atual.getPlano());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pixAprovadoAtivaPlanoEssencial() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.APROVADO);

        when(pagamentoRepository.buscarPorIdComBloqueio(30L))
                .thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.empty());
        when(assinaturaRepository.save(any(Assinatura.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));

        Assinatura resultado = service.ativarPlanoPagoPorPix(EMPRESA_ID, 30L);

        assertEquals(Assinatura.Plano.ESSENCIAL, resultado.getPlano());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertFalse(resultado.isTesteGratuito());
        assertFalse(resultado.isRenovacaoAutomatica());
        assertNull(resultado.getMercadoPagoAssinaturaId());
        assertNotNull(resultado.getDataInicio());
        assertNotNull(resultado.getDataVencimento());
        assertTrue(resultado.getDataVencimento().isAfter(resultado.getDataInicio()));
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());

        verify(assinaturaRepository).save(any(Assinatura.class));
        verify(pagamentoRepository).save(pagamento);
    }

    @Test
    void pixAprovadoAtivaPlanoProfissional() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.PROFISSIONAL,
                PagamentoAssinatura.Status.APROVADO);

        when(pagamentoRepository.buscarPorIdComBloqueio(31L))
                .thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.empty());
        when(assinaturaRepository.save(any(Assinatura.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));

        Assinatura resultado = service.ativarPlanoPagoPorPix(EMPRESA_ID, 31L);

        assertEquals(Assinatura.Plano.PROFISSIONAL, resultado.getPlano());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertFalse(resultado.isRenovacaoAutomatica());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());

        verify(assinaturaRepository).save(any(Assinatura.class));
        verify(pagamentoRepository).save(pagamento);
    }

    @Test
    void pixPendenteNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.PENDENTE);
        pagamento.setDataAprovacao(null);

        when(pagamentoRepository.buscarPorIdComBloqueio(32L))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 32L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void pixRecusadoNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.RECUSADO);
        pagamento.setDataAprovacao(null);

        when(pagamentoRepository.buscarPorIdComBloqueio(33L))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 33L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pixDeOutraEmpresaNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.APROVADO);
        pagamento.setEmpresaId(99L);

        when(pagamentoRepository.buscarPorIdComBloqueio(34L))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalArgumentException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 34L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pixComValorDivergenteNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.APROVADO);
        pagamento.setValor(new BigDecimal("79.90"));

        when(pagamentoRepository.buscarPorIdComBloqueio(35L))
                .thenReturn(Optional.of(pagamento));

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 35L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pixJaUtilizadoNaoRenovaNovamente() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL,
                PagamentoAssinatura.Status.APROVADO);

        pagamento.setDataVencimento(LocalDateTime.now().plusDays(30));

        Assinatura atual = new Assinatura();
        atual.setTipoConta(Assinatura.TipoConta.EMPRESA);
        atual.setContaId(EMPRESA_ID);
        atual.setPlano(Assinatura.Plano.ESSENCIAL);
        atual.setStatus(Assinatura.Status.ATIVA);
        atual.setTesteGratuito(false);
        atual.setDataVencimento(pagamento.getDataVencimento());
        atual.setRenovacaoAutomatica(false);

        when(pagamentoRepository.buscarPorIdComBloqueio(36L))
                .thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        Assinatura resultado = service.ativarPlanoPagoPorPix(EMPRESA_ID, 36L);

        assertSame(atual, resultado);
        assertEquals(pagamento.getDataVencimento(), resultado.getDataVencimento());

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void pixEntregadorAprovadoAtivaPlanoEssencial() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        prepararBloqueioEntregador();
        when(pagamentoRepository.buscarPorIdComBloqueio(40L)).thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.empty());
        when(assinaturaRepository.save(any(Assinatura.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));

        Assinatura resultado = service.ativarPlanoPagoPorPix(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 40L);

        assertEquals(Assinatura.TipoConta.ENTREGADOR, resultado.getTipoConta());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertEquals(Assinatura.Plano.ESSENCIAL, resultado.getPlano());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertFalse(resultado.isRenovacaoAutomatica());
        assertEquals(resultado.getDataInicio().plusDays(30), resultado.getDataVencimento());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        verify(pagamentoRepository).save(pagamento);
    }

    @Test
    void cartaoEntregadorAprovadoAtivaPlanoProfissional() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.PROFISSIONAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setMercadoPagoAssinaturaId("assinatura_entregador_123");
        prepararBloqueioEntregador();
        prepararRecorrencia(pagamento, Assinatura.TipoConta.ENTREGADOR,
                AssinaturaRecorrente.Status.AUTORIZADA);
        when(pagamentoRepository.buscarPorIdComBloqueio(41L)).thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.empty());
        when(assinaturaRepository.save(any(Assinatura.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));

        Assinatura resultado = service.ativarPlanoPagoPorCartao(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 41L);

        assertEquals(Assinatura.TipoConta.ENTREGADOR, resultado.getTipoConta());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertEquals(Assinatura.Plano.PROFISSIONAL, resultado.getPlano());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertTrue(resultado.isRenovacaoAutomatica());
        assertEquals(pagamento.getMercadoPagoAssinaturaId(), resultado.getMercadoPagoAssinaturaId());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        verify(pagamentoRepository).save(pagamento);
    }

    @Test
    void empresaNaoPodeUsarPagamentoDeEntregadorComMesmoId() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        when(pagamentoRepository.buscarPorIdComBloqueio(42L)).thenReturn(Optional.of(pagamento));

        assertThrows(IllegalArgumentException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 42L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void entregadorNaoPodeUsarPagamentoDeEmpresaComMesmoId() {
        PagamentoAssinatura pagamento = pagamentoPix(
                Assinatura.Plano.ESSENCIAL, PagamentoAssinatura.Status.APROVADO);
        prepararBloqueioEntregador();
        when(pagamentoRepository.buscarPorIdComBloqueio(43L)).thenReturn(Optional.of(pagamento));

        assertThrows(IllegalArgumentException.class,
                () -> service.ativarPlanoPagoPorPix(Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 43L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void entregadorComValorIncorretoNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        pagamento.setValor(new BigDecimal("39.90"));
        prepararBloqueioEntregador();
        when(pagamentoRepository.buscarPorIdComBloqueio(44L)).thenReturn(Optional.of(pagamento));

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorPix(Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 44L));

        assertEquals("Valor do pagamento inconsistente.", erro.getMessage());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void pagamentoComDoisTitularesNaoAtivaPlano() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        pagamento.setEmpresaId(EMPRESA_ID);
        when(pagamentoRepository.buscarPorIdComBloqueio(45L)).thenReturn(Optional.of(pagamento));

        assertThrows(IllegalArgumentException.class,
                () -> service.ativarPlanoPagoPorPix(EMPRESA_ID, 45L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void pagamentoEntregadorJaUtilizadoNaoRenovaNovamente() {
        PagamentoAssinatura pagamento = pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        pagamento.setDataVencimento(LocalDateTime.now().plusDays(30));
        Assinatura atual = new Assinatura();
        atual.setTipoConta(Assinatura.TipoConta.ENTREGADOR);
        atual.setContaId(EMPRESA_ID);
        atual.setPlano(Assinatura.Plano.ESSENCIAL);
        atual.setStatus(Assinatura.Status.ATIVA);
        atual.setTesteGratuito(false);
        atual.setDataVencimento(pagamento.getDataVencimento());
        prepararBloqueioEntregador();
        when(pagamentoRepository.buscarPorIdComBloqueio(46L)).thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        Assinatura resultado = service.ativarPlanoPagoPorPix(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 46L);

        assertSame(atual, resultado);
        assertEquals(pagamento.getDataVencimento(), resultado.getDataVencimento());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    @Test
    void cartaoEmpresaAutorizadoAtivaPlanoComRenovacao() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, null);
        AssinaturaRecorrente recorrente = prepararRecorrencia(pagamento,
                Assinatura.TipoConta.EMPRESA, AssinaturaRecorrente.Status.AUTORIZADA);
        permitirGravacaoAssinatura();

        Assinatura resultado = service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L);

        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertEquals(Assinatura.TipoConta.EMPRESA, resultado.getTipoConta());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertEquals(pagamento.getPlano(), resultado.getPlano());
        assertTrue(resultado.isRenovacaoAutomatica());
        assertEquals(pagamento.getMercadoPagoAssinaturaId(), resultado.getMercadoPagoAssinaturaId());
        assertEquals(resultado.getDataInicio().plusDays(30), resultado.getDataVencimento());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        verify(consultaRecorrencia).setLockMode(LockModeType.PESSIMISTIC_WRITE);
        verify(entityManager).refresh(recorrente, LockModeType.PESSIMISTIC_WRITE);
        verify(pagamentoRepository).save(pagamento);
    }

    @Test
    void mensalidadeEmpresaCanceladaProrrogaPeriodoSemReativarRenovacao() {
        verificarProrrogacaoCancelada(Assinatura.TipoConta.EMPRESA);
    }

    @Test
    void mensalidadeEntregadorCanceladaProrrogaPeriodoSemReativarRenovacao() {
        verificarProrrogacaoCancelada(Assinatura.TipoConta.ENTREGADOR);
    }

    @Test
    void primeiraMensalidadeCanceladaAtivaPlanoSemRenovacao() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, null);
        prepararRecorrencia(pagamento, Assinatura.TipoConta.EMPRESA,
                AssinaturaRecorrente.Status.CANCELADA);
        permitirGravacaoAssinatura();

        Assinatura resultado = service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L);

        verificarNovaAssinaturaSemRenovacao(resultado, pagamento, Assinatura.TipoConta.EMPRESA);
    }

    @Test
    void mensalidadeEncerradaDoEntregadorAtivaPeriodoPagoSemRenovacao() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.ENTREGADOR);
        prepararPagamentoCartao(Assinatura.TipoConta.ENTREGADOR, pagamento, null);
        prepararRecorrencia(pagamento, Assinatura.TipoConta.ENTREGADOR,
                AssinaturaRecorrente.Status.ENCERRADA);
        permitirGravacaoAssinatura();

        Assinatura resultado = service.ativarPlanoPagoPorCartao(
                Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 50L);

        verificarNovaAssinaturaSemRenovacao(resultado, pagamento, Assinatura.TipoConta.ENTREGADOR);
    }

    @Test
    void recorrenciaDeEmpresaNaoPodeAtivarPagamentoDeEntregadorComMesmoId() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.ENTREGADOR);
        prepararPagamentoCartao(Assinatura.TipoConta.ENTREGADOR, pagamento, null);
        prepararRecorrencia(pagamento, Assinatura.TipoConta.EMPRESA,
                AssinaturaRecorrente.Status.AUTORIZADA);

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(Assinatura.TipoConta.ENTREGADOR, EMPRESA_ID, 50L));

        assertEquals("A assinatura recorrente não pertence ao titular do pagamento.", erro.getMessage());
        verificarNenhumaAtivacao(pagamento);
    }

    @Test
    void recorrenciaDeOutroTitularDoMesmoTipoNaoAtivaPagamento() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, null);
        AssinaturaRecorrente recorrente = prepararRecorrencia(pagamento,
                Assinatura.TipoConta.EMPRESA, AssinaturaRecorrente.Status.AUTORIZADA);
        recorrente.setEmpresaId(99L);

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L));

        assertEquals("A assinatura recorrente não pertence ao titular do pagamento.", erro.getMessage());
        verificarNenhumaAtivacao(pagamento);
    }

    @Test
    void recorrenciaNaoEncontradaNaoAtivaPagamento() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, null);
        prepararConsultaRecorrencia(pagamento.getMercadoPagoAssinaturaId(), List.of());

        IllegalStateException erro = assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L));

        assertEquals("Não foi possível identificar a assinatura recorrente do pagamento.", erro.getMessage());
        verificarNenhumaAtivacao(pagamento);
    }

    @Test
    void mensalidadeCanceladaJaUtilizadaNaoProrrogaNovamente() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setRenovacaoAutomatica(false);
        pagamento.setDataVencimento(atual.getDataVencimento());
        LocalDateTime vencimento = atual.getDataVencimento();
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, atual);

        Assinatura resultado = service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L);

        assertSame(atual, resultado);
        assertEquals(vencimento, resultado.getDataVencimento());
        assertFalse(resultado.isRenovacaoAutomatica());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
        verifyNoInteractions(consultaRecorrencia);
    }

    @Test
    void mensalidadeAntigaNaoSubstituiRecorrenciaMaisRecente() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setMercadoPagoAssinaturaId("assinatura_nova");
        LocalDateTime vencimento = atual.getDataVencimento();
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, atual);

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L));

        assertTrue(atual.isRenovacaoAutomatica());
        assertEquals("assinatura_nova", atual.getMercadoPagoAssinaturaId());
        assertEquals(vencimento, atual.getDataVencimento());
        verificarNenhumaAtivacao(pagamento);
        verifyNoInteractions(consultaRecorrencia);
    }

    @Test
    void cancelamentoConfirmadoNoRefreshImpedeReativacaoDeEstadoAntigo() {
        PagamentoAssinatura pagamento = pagamentoCartao(Assinatura.TipoConta.EMPRESA);
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        LocalDateTime vencimento = atual.getDataVencimento();
        prepararPagamentoCartao(Assinatura.TipoConta.EMPRESA, pagamento, atual);
        AssinaturaRecorrente recorrente = prepararRecorrencia(pagamento,
                Assinatura.TipoConta.EMPRESA, AssinaturaRecorrente.Status.AUTORIZADA);
        doAnswer(invocacao -> {
            recorrente.setStatus(AssinaturaRecorrente.Status.CANCELADA);
            return null;
        }).when(entityManager).refresh(recorrente, LockModeType.PESSIMISTIC_WRITE);
        permitirGravacaoAssinatura();

        Assinatura resultado = service.ativarPlanoPagoPorCartao(EMPRESA_ID, 50L);

        assertSame(atual, resultado);
        assertFalse(resultado.isRenovacaoAutomatica());
        assertEquals(vencimento.plusDays(30), resultado.getDataVencimento());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        verify(entityManager).refresh(recorrente, LockModeType.PESSIMISTIC_WRITE);
    }

    private void verificarProrrogacaoCancelada(Assinatura.TipoConta tipoConta) {
        PagamentoAssinatura pagamento = pagamentoCartao(tipoConta);
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setTipoConta(tipoConta);
        atual.setRenovacaoAutomatica(false);
        LocalDateTime inicio = atual.getDataInicio();
        LocalDateTime vencimento = atual.getDataVencimento();
        prepararPagamentoCartao(tipoConta, pagamento, atual);
        prepararRecorrencia(pagamento, tipoConta, AssinaturaRecorrente.Status.CANCELADA);
        permitirGravacaoAssinatura();

        Assinatura resultado = service.ativarPlanoPagoPorCartao(tipoConta, EMPRESA_ID, 50L);

        assertSame(atual, resultado);
        assertEquals(tipoConta, resultado.getTipoConta());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertEquals(Assinatura.Plano.ESSENCIAL, resultado.getPlano());
        assertEquals(inicio, resultado.getDataInicio());
        assertEquals(vencimento.plusDays(30), resultado.getDataVencimento());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        assertFalse(resultado.isRenovacaoAutomatica());
        assertEquals(pagamento.getMercadoPagoAssinaturaId(), resultado.getMercadoPagoAssinaturaId());
        verify(assinaturaRepository).save(atual);
        verify(pagamentoRepository).save(pagamento);
    }

    private void verificarNovaAssinaturaSemRenovacao(Assinatura resultado,
                                                     PagamentoAssinatura pagamento, Assinatura.TipoConta tipoConta) {
        assertEquals(tipoConta, resultado.getTipoConta());
        assertEquals(EMPRESA_ID, resultado.getContaId());
        assertEquals(Assinatura.Status.ATIVA, resultado.getStatus());
        assertEquals(pagamento.getPlano(), resultado.getPlano());
        assertFalse(resultado.isTesteGratuito());
        assertFalse(resultado.isRenovacaoAutomatica());
        assertEquals(pagamento.getMercadoPagoAssinaturaId(), resultado.getMercadoPagoAssinaturaId());
        assertEquals(resultado.getDataInicio().plusDays(30), resultado.getDataVencimento());
        assertEquals(resultado.getDataVencimento(), pagamento.getDataVencimento());
        verify(assinaturaRepository).save(resultado);
        verify(pagamentoRepository).save(pagamento);
    }

    private void verificarNenhumaAtivacao(PagamentoAssinatura pagamento) {
        assertNull(pagamento.getDataVencimento());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
        verify(pagamentoRepository, never()).save(any(PagamentoAssinatura.class));
    }

    private void prepararPagamentoCartao(Assinatura.TipoConta tipoConta,
                                         PagamentoAssinatura pagamento, Assinatura atual) {
        if (tipoConta == Assinatura.TipoConta.ENTREGADOR) {
            prepararBloqueioEntregador();
        }
        when(pagamentoRepository.buscarPorIdComBloqueio(50L)).thenReturn(Optional.of(pagamento));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                tipoConta, EMPRESA_ID, Assinatura.Status.ATIVA)).thenReturn(Optional.ofNullable(atual));
    }

    private void permitirGravacaoAssinatura() {
        when(assinaturaRepository.save(any(Assinatura.class)))
                .thenAnswer(invocacao -> invocacao.getArgument(0));
    }

    private PagamentoAssinatura pagamentoCartao(Assinatura.TipoConta tipoConta) {
        PagamentoAssinatura pagamento = tipoConta == Assinatura.TipoConta.EMPRESA
                ? pagamentoPix(Assinatura.Plano.ESSENCIAL, PagamentoAssinatura.Status.APROVADO)
                : pagamentoEntregador(Assinatura.Plano.ESSENCIAL);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.CARTAO);
        pagamento.setMercadoPagoAssinaturaId("assinatura_123");
        return pagamento;
    }

    private AssinaturaRecorrente prepararRecorrencia(PagamentoAssinatura pagamento,
                                                     Assinatura.TipoConta tipoConta, AssinaturaRecorrente.Status status) {
        AssinaturaRecorrente recorrente = new AssinaturaRecorrente();
        recorrente.setId(55L);
        if (tipoConta == Assinatura.TipoConta.EMPRESA) {
            recorrente.setEmpresaId(EMPRESA_ID);
        } else {
            recorrente.setEntregadorId(EMPRESA_ID);
        }
        recorrente.setPlano(pagamento.getPlano());
        recorrente.setValor(AssinaturaService.valorDoPlano(tipoConta, pagamento.getPlano()));
        recorrente.setMercadoPagoAssinaturaId(pagamento.getMercadoPagoAssinaturaId());
        recorrente.setStatus(status);
        recorrente.setEstadoCriacao(AssinaturaRecorrente.EstadoCriacao.CONFIRMADA);
        prepararConsultaRecorrencia(pagamento.getMercadoPagoAssinaturaId(), List.of(recorrente));
        return recorrente;
    }

    private void prepararConsultaRecorrencia(String idExterno, List<AssinaturaRecorrente> registros) {
        when(entityManager.createQuery(
                "select r from AssinaturaRecorrente r where r.mercadoPagoAssinaturaId = :assinaturaExterna",
                AssinaturaRecorrente.class)).thenReturn(consultaRecorrencia);
        when(consultaRecorrencia.setParameter("assinaturaExterna", idExterno))
                .thenReturn(consultaRecorrencia);
        when(consultaRecorrencia.setLockMode(LockModeType.PESSIMISTIC_WRITE))
                .thenReturn(consultaRecorrencia);
        when(consultaRecorrencia.getResultList()).thenReturn(registros);
    }

    private void prepararBloqueioEntregador() {
        when(entityManager.find(Usuario.class, EMPRESA_ID, LockModeType.PESSIMISTIC_WRITE))
                .thenReturn(mock(Usuario.class));
    }

    private PagamentoAssinatura pagamentoEntregador(Assinatura.Plano plano) {
        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEntregadorId(EMPRESA_ID);
        pagamento.setPlano(plano);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(PagamentoAssinatura.Status.APROVADO);
        pagamento.setValor(plano == Assinatura.Plano.ESSENCIAL
                ? new BigDecimal("9.90") : new BigDecimal("19.90"));
        pagamento.setMercadoPagoPagamentoId("12345");
        pagamento.setDataAprovacao(LocalDateTime.now());
        return pagamento;
    }

    private PagamentoAssinatura pagamentoPix(
            Assinatura.Plano plano,
            PagamentoAssinatura.Status status) {

        PagamentoAssinatura pagamento = new PagamentoAssinatura();
        pagamento.setEmpresaId(EMPRESA_ID);
        pagamento.setPlano(plano);
        pagamento.setFormaPagamento(PagamentoAssinatura.FormaPagamento.PIX);
        pagamento.setStatus(status);
        pagamento.setValor(plano == Assinatura.Plano.ESSENCIAL
                ? new BigDecimal("39.90")
                : new BigDecimal("79.90"));
        pagamento.setMercadoPagoPagamentoId("12345");
        pagamento.setDataAprovacao(LocalDateTime.now());

        return pagamento;
    }

    private Assinatura assinaturaPaga(Assinatura.Plano plano) {
        Assinatura assinatura = new Assinatura();
        assinatura.setTipoConta(Assinatura.TipoConta.EMPRESA);
        assinatura.setContaId(EMPRESA_ID);
        assinatura.setPlano(plano);
        assinatura.setStatus(Assinatura.Status.ATIVA);
        assinatura.setTesteGratuito(false);
        assinatura.setDataInicio(LocalDateTime.now().minusDays(5));
        assinatura.setDataVencimento(LocalDateTime.now().plusDays(25));
        assinatura.setRenovacaoAutomatica(true);
        assinatura.setMercadoPagoAssinaturaId("assinatura_123");
        return assinatura;
    }
}
