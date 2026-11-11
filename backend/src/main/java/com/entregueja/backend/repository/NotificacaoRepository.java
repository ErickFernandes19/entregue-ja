package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Notificacao;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface NotificacaoRepository extends JpaRepository<Notificacao, Long> {

    Page<Notificacao> findByTipoContaAndContaId(
            String tipoConta,
            Long contaId,
            Pageable pageable
    );

    long countByTipoContaAndContaIdAndLidaFalse(
            String tipoConta,
            Long contaId
    );

    Optional<Notificacao> findByIdAndTipoContaAndContaId(
            Long id,
            String tipoConta,
            Long contaId
    );
}
