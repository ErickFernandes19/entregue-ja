package com.entregueja.backend.repository;

import com.entregueja.backend.entity.AssinaturaRecorrente;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface AssinaturaRecorrenteRepository extends JpaRepository<AssinaturaRecorrente, Long> {

    List<AssinaturaRecorrente> findByEmpresaIdOrderByIdDesc(Long empresaId);

    Optional<AssinaturaRecorrente> findByChaveIdempotencia(String chaveIdempotencia);

    Optional<AssinaturaRecorrente> findByMercadoPagoAssinaturaId(String mercadoPagoAssinaturaId);

    Optional<AssinaturaRecorrente> findFirstByEmpresaIdAndStatusInOrderByIdDesc(
            Long empresaId,
            List<AssinaturaRecorrente.Status> status
    );

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from AssinaturaRecorrente a where a.id = :id")
    Optional<AssinaturaRecorrente> buscarPorIdComBloqueio(@Param("id") Long id);
}
