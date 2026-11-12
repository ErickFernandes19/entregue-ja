package com.entregueja.backend.repository;

import com.entregueja.backend.entity.TentativaEntrega;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface TentativaEntregaRepository
        extends JpaRepository<TentativaEntrega, Long> {

    List<TentativaEntrega> findByEntregaIdOrderByNumeroTentativaAsc(
            Long entregaId
    );

    long countByEntregaId(Long entregaId);

    Optional<TentativaEntrega> findTopByEntregaIdOrderByNumeroTentativaDesc(
            Long entregaId
    );
}