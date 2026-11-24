package com.entregueja.backend.repository;

import com.entregueja.backend.entity.PagamentoAssinatura;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PagamentoAssinaturaRepository extends JpaRepository<PagamentoAssinatura, Long> {

    List<PagamentoAssinatura> findByEmpresaIdOrderByDataCriacaoDesc(Long empresaId);

    List<PagamentoAssinatura> findByEntregadorIdOrderByDataCriacaoDesc(Long entregadorId);

    Optional<PagamentoAssinatura> findByChaveIdempotencia(String chaveIdempotencia);

    boolean existsByChaveIdempotencia(String chaveIdempotencia);

    Optional<PagamentoAssinatura> findByMercadoPagoPagamentoId(String mercadoPagoPagamentoId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from PagamentoAssinatura p where p.mercadoPagoPagamentoId = :mercadoPagoPagamentoId")
    Optional<PagamentoAssinatura> buscarPorMercadoPagoPagamentoIdComBloqueio(
            @Param("mercadoPagoPagamentoId") String mercadoPagoPagamentoId
    );

    List<PagamentoAssinatura> findByMercadoPagoAssinaturaIdOrderByDataCriacaoDesc(String mercadoPagoAssinaturaId);

    List<PagamentoAssinatura> findByEmpresaIdAndStatusOrderByDataCriacaoDesc(
            Long empresaId,
            PagamentoAssinatura.Status status
    );

    List<PagamentoAssinatura> findByEntregadorIdAndStatusOrderByDataCriacaoDesc(
            Long entregadorId,
            PagamentoAssinatura.Status status
    );

    List<PagamentoAssinatura> findByMercadoPagoAssinaturaIdAndStatusOrderByDataCriacaoDesc(
            String mercadoPagoAssinaturaId,
            PagamentoAssinatura.Status status
    );

    List<PagamentoAssinatura> findByStatusOrderByDataCriacaoAsc(PagamentoAssinatura.Status status);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from PagamentoAssinatura p where p.id = :id")
    Optional<PagamentoAssinatura> buscarPorIdComBloqueio(@Param("id") Long id);
}
