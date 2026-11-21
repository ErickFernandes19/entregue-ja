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
        lenient().when(entityManager.find(eq(Empresa.class), eq(EMPRESA_ID), eq(LockModeType.PESSIMISTIC_WRITE)))
                .thenReturn(new Empresa());
    }

    @Test
    void agendarUpgradePreservaPlanoEVencimento() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        LocalDateTime vencimento = atual.getDataVencimento();
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));
        when(assinaturaRepository.save(atual)).thenReturn(atual);

        Assinatura resultado = service.agendarTrocaPlano(EMPRESA_ID, Assinatura.Plano.PROFISSIONAL);

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
                Assinatura.TipoConta.EMPRESA, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));
        when(assinaturaRepository.save(atual)).thenReturn(atual);

        service.agendarTrocaPlano(EMPRESA_ID, Assinatura.Plano.ESSENCIAL);

        assertEquals(Assinatura.Plano.PROFISSIONAL, atual.getPlano());
        assertEquals(Assinatura.Plano.ESSENCIAL, atual.getPlanoAgendado());
        assertEquals(atual.getDataVencimento(), atual.getDataTrocaAgendada());
    }

    @Test
    void naoPermiteAgendarMesmoPlano() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        assertThrows(IllegalArgumentException.class,
                () -> service.agendarTrocaPlano(EMPRESA_ID, Assinatura.Plano.ESSENCIAL));
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
    }

    @Test
    void cancelarTrocaMantemPlanoAtual() {
        Assinatura atual = assinaturaPaga(Assinatura.Plano.ESSENCIAL);
        atual.setPlanoAgendado(Assinatura.Plano.PROFISSIONAL);
        atual.setDataTrocaAgendada(atual.getDataVencimento());
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, EMPRESA_ID, Assinatura.Status.ATIVA))
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
        when(pagamentoRepository.buscarPorIdComBloqueio(20L)).thenReturn(Optional.of(pagamento));
        when(pagamento.getEmpresaId()).thenReturn(EMPRESA_ID);
        when(pagamento.getFormaPagamento()).thenReturn(PagamentoAssinatura.FormaPagamento.CARTAO);
        when(pagamento.getStatus()).thenReturn(PagamentoAssinatura.Status.RECUSADO);

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
        when(pagamentoRepository.buscarPorIdComBloqueio(21L)).thenReturn(Optional.of(pagamento));
        when(pagamento.getEmpresaId()).thenReturn(EMPRESA_ID);
        when(pagamento.getFormaPagamento()).thenReturn(PagamentoAssinatura.FormaPagamento.CARTAO);
        when(pagamento.getStatus()).thenReturn(PagamentoAssinatura.Status.APROVADO);
        when(pagamento.getDataAprovacao()).thenReturn(LocalDateTime.now());
        when(pagamento.getMercadoPagoPagamentoId()).thenReturn("12345");
        when(pagamento.getMercadoPagoAssinaturaId()).thenReturn("assinatura_123");
        when(pagamento.getPlano()).thenReturn(Assinatura.Plano.PROFISSIONAL);
        when(pagamento.getValor()).thenReturn(new BigDecimal("79.90"));
        when(assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                Assinatura.TipoConta.EMPRESA, EMPRESA_ID, Assinatura.Status.ATIVA))
                .thenReturn(Optional.of(atual));

        assertThrows(IllegalStateException.class,
                () -> service.ativarPlanoPagoPorCartao(EMPRESA_ID, 21L));
        assertEquals(Assinatura.Plano.ESSENCIAL, atual.getPlano());
        verify(assinaturaRepository, never()).save(any(Assinatura.class));
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
