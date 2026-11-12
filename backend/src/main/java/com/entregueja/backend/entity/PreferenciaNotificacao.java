
package com.entregueja.backend.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "preferencias_notificacao",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_preferencia_notificacao_conta",
                columnNames = {"tipo_conta", "conta_id"}
        ),
        indexes = @Index(
                name = "idx_preferencia_notificacao_conta",
                columnList = "tipo_conta, conta_id"
        )
)
public class PreferenciaNotificacao {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tipo_conta", nullable = false, length = 20)
    private String tipoConta;

    @Column(name = "conta_id", nullable = false)
    private Long contaId;

    @Column(name = "entrega_concluida", nullable = false)
    private boolean entregaConcluida = true;

    @Column(name = "entrega_cancelada", nullable = false)
    private boolean entregaCancelada = true;

    @Column(name = "entrega_nao_realizada", nullable = false)
    private boolean entregaNaoRealizada = true;

    @Column(name = "novo_entregador", nullable = false)
    private boolean novoEntregador = true;

    @Column(name = "solicitacoes", nullable = false)
    private boolean solicitacoes = true;

    @Column(name = "nova_entrega", nullable = false)
    private boolean novaEntrega = true;

    @Column(name = "vinculos", nullable = false)
    private boolean vinculos = true;

    @Column(name = "sons", nullable = false)
    private boolean sons = true;

    @Column(name = "vibracao", nullable = false)
    private boolean vibracao = true;

    @Column(name = "criado_em", nullable = false, updatable = false)
    private LocalDateTime criadoEm;

    @Column(name = "atualizado_em", nullable = false)
    private LocalDateTime atualizadoEm;

    public PreferenciaNotificacao() {
    }

    public PreferenciaNotificacao(String tipoConta, Long contaId) {
        this.tipoConta = tipoConta;
        this.contaId = contaId;
    }

    @PrePersist
    public void antesDeCriar() {
        LocalDateTime agora = LocalDateTime.now();
        criadoEm = agora;
        atualizadoEm = agora;
    }

    @PreUpdate
    public void antesDeAtualizar() {
        atualizadoEm = LocalDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getTipoConta() {
        return tipoConta;
    }

    public void setTipoConta(String tipoConta) {
        this.tipoConta = tipoConta;
    }

    public Long getContaId() {
        return contaId;
    }

    public void setContaId(Long contaId) {
        this.contaId = contaId;
    }

    public boolean isEntregaConcluida() {
        return entregaConcluida;
    }

    public void setEntregaConcluida(boolean entregaConcluida) {
        this.entregaConcluida = entregaConcluida;
    }

    public boolean isEntregaCancelada() {
        return entregaCancelada;
    }

    public void setEntregaCancelada(boolean entregaCancelada) {
        this.entregaCancelada = entregaCancelada;
    }

    public boolean isEntregaNaoRealizada() {
        return entregaNaoRealizada;
    }

    public void setEntregaNaoRealizada(boolean entregaNaoRealizada) {
        this.entregaNaoRealizada = entregaNaoRealizada;
    }

    public boolean isNovoEntregador() {
        return novoEntregador;
    }

    public void setNovoEntregador(boolean novoEntregador) {
        this.novoEntregador = novoEntregador;
    }

    public boolean isSolicitacoes() {
        return solicitacoes;
    }

    public void setSolicitacoes(boolean solicitacoes) {
        this.solicitacoes = solicitacoes;
    }

    public boolean isNovaEntrega() {
        return novaEntrega;
    }

    public void setNovaEntrega(boolean novaEntrega) {
        this.novaEntrega = novaEntrega;
    }

    public boolean isVinculos() {
        return vinculos;
    }

    public void setVinculos(boolean vinculos) {
        this.vinculos = vinculos;
    }

    public boolean isSons() {
        return sons;
    }

    public void setSons(boolean sons) {
        this.sons = sons;
    }

    public boolean isVibracao() {
        return vibracao;
    }

    public void setVibracao(boolean vibracao) {
        this.vibracao = vibracao;
    }

    public LocalDateTime getCriadoEm() {
        return criadoEm;
    }

    public void setCriadoEm(LocalDateTime criadoEm) {
        this.criadoEm = criadoEm;
    }

    public LocalDateTime getAtualizadoEm() {
        return atualizadoEm;
    }

    public void setAtualizadoEm(LocalDateTime atualizadoEm) {
        this.atualizadoEm = atualizadoEm;
    }
}
