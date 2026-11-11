package com.entregueja.backend.repository;

import com.entregueja.backend.entity.DispositivoFcm;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface DispositivoFcmRepository extends JpaRepository<DispositivoFcm, Long> {

    Optional<DispositivoFcm> findByToken(String token);

    List<DispositivoFcm> findByTipoContaAndContaId(String tipoConta, Long contaId);

    long deleteByTokenAndTipoContaAndContaId(
            String token,
            String tipoConta,
            Long contaId
    );
}
