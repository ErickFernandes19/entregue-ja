package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.PagamentoAssinatura;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.PagamentoAssinaturaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
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
        PagamentoAssinatura pagamento = mock(PagamentoAssinatura.class);

        when(pagamentoRepository.buscarPorIdComBloqueio(20L))
                .thenReturn(Optional.of(pagamento));
        when(pagamento.getEmpresaId()).thenReturn(EMPRESA_ID);
        when(pagamento.getFormaPagamento())
                .thenReturn(PagamentoAssinatura.FormaPagamento.CARTAO);
        when(pagamento.getStatus())
                .thenReturn(PagamentoAssinatura.Status.RECUSADO);

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 20L));

        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void pagamentoAprovadoNaoPodeSerAplicadoAntesDaTroca() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        atual.setDataTrocaAgendada(atual.getDataVencimento());

        PagamentoAssinatura pagamento = mock(PagamentoAssinatura.class);

        when(pagamentoRepository.buscarPorIdComBloqueio(21L))
                .thenReturn(Optional.of(pagamento));
        when(pagamento.getEmpresaId()).thenReturn(EMPRESA_ID);
        when(pagamento.getFormaPagamento())
                .thenReturn(PagamentoAssinatura.FormaPagamento.CARTAO);
        when(pagamento.getStatus())
                .thenReturn(PagamentoAssinatura.Status.APROVADO);
        when(pagamento.getDataAprovacao()).thenReturn(LocalDateTime.now());
        when(pagamento.getMercadoPagoPagamentoId()).thenReturn("12345");
        when(pagamento.getMercadoPagoAssinaturaId())
                .thenReturn("assinatura_123");
        when(pagamento.getPlano())
                .thenReturn(Assinatura.Plano.PROFISSIONAL);
        when(pagamento.getValor())
                .thenReturn(new BigDecimal("79.90"));

        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA,
                EMPRESA_ID,
                Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 21L));

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