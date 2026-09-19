package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Entrega;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EntregaRepository extends JpaRepository<Entrega, Long> {

    long countByEntregue(boolean entregue);

    List<Entrega> findByEmpresa(Empresa empresa);

    long countByEmpresa(Empresa empresa);

    long countByEmpresaAndEntregue(Empresa empresa, boolean entregue);

    long countByEmpresaAndStatus(Empresa empresa, String status);

    List<Entrega> findByEntregador(Usuario usuario);

    long countByEntregador(Usuario usuario);

    long countByEmpresaAndStatusNot(Empresa empresa, String status);
}