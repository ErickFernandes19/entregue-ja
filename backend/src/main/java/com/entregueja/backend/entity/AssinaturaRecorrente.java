package com.entregueja.backend.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(
        name = "assinaturas_recorrentes",
        indexes = {
                @Index(name = "idx_assinatura_recorrente_empresa", columnList = "empresa_id"),
                @Index(name = "idx_assinatura_recorrente_status", columnList = "status")
        },
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_assinatura_recorrente_mp", columnNames = "mercado_pago_assinatura_id"),
                @UniqueConstraint(name = "uk_assinatura_recorrente_chave", columnNames = "chave_idempotencia")
        }
)
public class AssinaturaRecorrente {

    public enum Status {
        PENDENTE,
        AUTORIZADA,
        PAUSADA,
        CANCELADA,
        ENCERRADA
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "empresa_id", nullable = false)
    private Long empresaId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    private Assinatura.Plano plano;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Status status = Status.PENDENTE;

    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal valor;

    @Column(name = "mercado_pago_assinatura_id", length = 150)
    private String mercadoPagoAssinaturaId;

    @Column(name = "chave_idempotencia", nullable = false, length = 100)
    private String chaveIdempotencia;

    @Column(name = "url_autorizacao", length = 2048)
    private String urlAutorizacao;

    @Column(name = "data_criacao", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @Column(name = "data_atualizacao", nullable = false)
    private LocalDateTime dataAtualizacao;

    @Column(name = "data_cancelamento")
    private LocalDateTime dataCancelamento;

    @PrePersist
    public void antesDeCriar() {
        LocalDateTime agora = LocalDateTime.now();
        dataCriacao = agora;
        dataAtualizacao = agora;
    }

    @PreUpdate
    public void antesDeAtualizar() {
        dataAtualizacao = LocalDateTime.now();
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getEmpresaId() { return empresaId; }
    public void setEmpresaId(Long empresaId) { this.empresaId = empresaId; }

    public Assinatura.Plano getPlano() { return plano; }
    public void setPlano(Assinatura.Plano plano) { this.plano = plano; }

    public Status getStatus() { return status; }
    public void setStatus(Status status) { this.status = status; }

    public BigDecimal getValor() { return valor; }
    public void setValor(BigDecimal valor) { this.valor = valor; }

    public String getMercadoPagoAssinaturaId() { return mercadoPagoAssinaturaId; }
    public void setMercadoPagoAssinaturaId(String mercadoPagoAssinaturaId) { this.mercadoPagoAssinaturaId = mercadoPagoAssinaturaId; }

    public String getChaveIdempotencia() { return chaveIdempotencia; }
    public void setChaveIdempotencia(String chaveIdempotencia) { this.chaveIdempotencia = chaveIdempotencia; }

    public String getUrlAutorizacao() { return urlAutorizacao; }
    public void setUrlAutorizacao(String urlAutorizacao) { this.urlAutorizacao = urlAutorizacao; }

    public LocalDateTime getDataCriacao() { return dataCriacao; }
    public void setDataCriacao(LocalDateTime dataCriacao) { this.dataCriacao = dataCriacao; }

    public LocalDateTime getDataAtualizacao() { return dataAtualizacao; }
    public void setDataAtualizacao(LocalDateTime dataAtualizacao) { this.dataAtualizacao = dataAtualizacao; }

    public LocalDateTime getDataCancelamento() { return dataCancelamento; }
    public void setDataCancelamento(LocalDateTime dataCancelamento) { this.dataCancelamento = dataCancelamento; }
}
