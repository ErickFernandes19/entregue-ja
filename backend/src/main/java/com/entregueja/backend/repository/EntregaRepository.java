
package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface EntregaRepository extends JpaRepository<Entrega, Long> {

    long countByEntregue(boolean entregue);

    List<Entrega> findByEmpresa(Empresa empresa);

    long countByEmpresa(Empresa empresa);

    long countByEmpresaAndEntregue(Empresa empresa, boolean entregue);

    long countByEmpresaAndStatus(Empresa empresa, String status);

    List<Entrega> findByEntregador(Usuario usuario);

    long countByEntregador(Usuario usuario);

    long countByEmpresaAndStatusNot(Empresa empresa, String status);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT e FROM Entrega e WHERE e.id = :id")
    Optional<Entrega> buscarPorIdComBloqueio(@Param("id") Long id);
}
