-- 1. ENUM para tipo de vaga
CREATE TYPE tipo_vaga_enum AS ENUM ('PcD', 'Autista', 'Gestante', 'Idoso');

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT USAGE ON TYPE tipo_vaga_enum TO anon, authenticated;

-- 2. Tabela de Locais
CREATE TABLE locais (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    latitude numeric(10, 7) NOT NULL,
    longitude numeric(10, 7) NOT NULL,
    referencia text,
    logradouro text NOT NULL,
    numero text NOT NULL,
    bairro text NOT NULL,
    cidade text NOT NULL,
    estado text NOT NULL,
    data_criacao timestamp with time zone DEFAULT now(),
    -- Referência ao Auth do Supabase (Criador do ponto no mapa)
    id_usuario_criador uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 3. Tabela de Vagas (Agora centraliza a foto e auditoria de edição)
CREATE TABLE vagas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_local uuid NOT NULL,
    tipo_vaga tipo_vaga_enum NOT NULL, 
    quantidade integer NOT NULL DEFAULT 1,
    
    -- Novos campos de imagem e auditoria
    foto_url text,
    id_usuario_ultima_alteracao uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    data_ultima_alteracao timestamp with time zone,

    CONSTRAINT fk_local
        FOREIGN KEY (id_local)
        REFERENCES locais(id)
        ON DELETE CASCADE,
    CONSTRAINT unique_tipo_por_local UNIQUE (id_local, tipo_vaga) 
);

-- 4. Tabela de Contribuições (Histórico de quem interagiu com o local)
CREATE TABLE contribuicoes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  id_usuario uuid REFERENCES auth.users(id) NOT NULL,
  id_local uuid REFERENCES locais(id) ON DELETE CASCADE NOT NULL,
  data_contribuicao timestamp with time zone DEFAULT now(),
  
  UNIQUE(id_usuario, id_local) 
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE locais TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE vagas TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE contribuicoes TO anon, authenticated;

-- 5. View para facilitar o consumo no Front-end
CREATE OR REPLACE VIEW locais_com_vagas AS
SELECT
  l.id,
  l.id_usuario_criador, 
  l.latitude,
  l.longitude,
  l.logradouro,
  l.numero,
  l.bairro,
  l.cidade,
  l.estado,
  l.referencia,
  l.data_criacao,      
  json_agg(
    json_build_object(
      'id_vaga', v.id,
      'tipo_vaga', v.tipo_vaga,
      'quantidade', v.quantidade,
      'foto_url', v.foto_url,
      'editado_por', v.id_usuario_ultima_foto,
      'data_foto', v.data_ultima_foto
    )
  ) AS vagas
FROM locais l
LEFT JOIN vagas v ON v.id_local = l.id
GROUP BY l.id;

GRANT SELECT ON TABLE locais_com_vagas TO anon, authenticated;

-- 6. Índices para Performance
CREATE INDEX idx_locais_coords ON locais(latitude, longitude);
CREATE INDEX idx_vagas_local ON vagas(id_local);