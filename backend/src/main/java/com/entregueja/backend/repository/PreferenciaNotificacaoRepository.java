
package com.entregueja.backend.repository;

import com.entregueja.backend.entity.PreferenciaNotificacao;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface PreferenciaNotificacaoRepository extends JpaRepository<PreferenciaNotificacao, Long> {

    Optional<PreferenciaNotificacao> findByTipoContaAndContaId(
            String tipoConta,
            Long contaId
    );
}
