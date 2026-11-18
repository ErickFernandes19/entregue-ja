package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Assinatura;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface AssinaturaRepository extends JpaRepository<Assinatura, Long> {

    List<Assinatura> findByTipoContaAndContaIdOrderByIdDesc(
            Assinatura.TipoConta tipoConta,
            Long contaId
    );

    Optional<Assinatura> findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
            Assinatura.TipoConta tipoConta,
            Long contaId,
            Assinatura.Status status
    );

    boolean existsByTipoContaAndContaIdAndStatus(
            Assinatura.TipoConta tipoConta,
            Long contaId,
            Assinatura.Status status
    );
}
