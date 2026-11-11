CREATE TABLE Kullanicilar (
    KullaniciID INT PRIMARY KEY IDENTITY(1,1),
    AdSoyad NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE NOT NULL,
    Sifre NVARCHAR(255) NOT NULL,
    Rol NVARCHAR(20) DEFAULT 'Müşteri',
    KayitTarihi DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Kategoriler (
    KategoriID INT PRIMARY KEY IDENTITY(1,1),
    KategoriAdi NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE Yazarlar (
    YazarID INT PRIMARY KEY IDENTITY(1,1),
    YazarAdi NVARCHAR(100) NOT NULL,
    Biyografi NVARCHAR(MAX)
);
GO

CREATE TABLE Yayinevleri (
    YayineviID INT PRIMARY KEY IDENTITY(1,1),
    YayineviAdi NVARCHAR(100) NOT NULL,
    IletisimBilgisi NVARCHAR(255)
);
GO

CREATE TABLE Kitaplar (
    KitapID INT PRIMARY KEY IDENTITY(1,1),
    KitapAdi NVARCHAR(255) NOT NULL,
    YazarID INT NOT NULL,
    KategoriID INT NOT NULL,
    YayineviID INT NOT NULL,
    Fiyat DECIMAL(18,2) NOT NULL CHECK (Fiyat >= 0), -- Eksi fiyat girilemez
    StokMiktari INT NOT NULL DEFAULT 0 CHECK (StokMiktari >= 0), -- Stok eksiye düşemez
    FOREIGN KEY (YazarID) REFERENCES Yazarlar(YazarID),
    FOREIGN KEY (KategoriID) REFERENCES Kategoriler(KategoriID),
    FOREIGN KEY (YayineviID) REFERENCES Yayinevleri(YayineviID)
);
GO

CREATE TABLE Siparisler (
    SiparisID INT PRIMARY KEY IDENTITY(1,1),
    KullaniciID INT NOT NULL,
    SiparisTarihi DATETIME DEFAULT GETDATE(),
    ToplamTutar DECIMAL(18,2) NOT NULL DEFAULT 0, -- Trigger ile hesaplanacak
    Durum NVARCHAR(50) DEFAULT 'Onay Bekliyor',
    FOREIGN KEY (KullaniciID) REFERENCES Kullanicilar(KullaniciID)
);
GO

CREATE TABLE SiparisDetaylari (
    SiparisDetayID INT PRIMARY KEY IDENTITY(1,1),
    SiparisID INT NOT NULL,
    KitapID INT NOT NULL,
    Adet INT NOT NULL CHECK (Adet > 0),
    BirimFiyati DECIMAL(18,2) NOT NULL,
    FOREIGN KEY (SiparisID) REFERENCES Siparisler(SiparisID),
    FOREIGN KEY (KitapID) REFERENCES Kitaplar(KitapID)
);
GO

CREATE TABLE Odemeler (
    OdemeID INT PRIMARY KEY IDENTITY(1,1),
    SiparisID INT NOT NULL,
    OdemeTarihi DATETIME DEFAULT GETDATE(),
    OdemeYontemi NVARCHAR(50) NOT NULL, 
    OdenenTutar DECIMAL(18,2) NOT NULL CHECK (OdenenTutar > 0),
    FOREIGN KEY (SiparisID) REFERENCES Siparisler(SiparisID)
);
GO

CREATE TRIGGER trg_StokKontrolVeDusur
ON SiparisDetaylari
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN Kitaplar k ON i.KitapID = k.KitapID
        WHERE k.StokMiktari < i.Adet
    )
    BEGIN
        RAISERROR ('Sipariş edilen bazı kitaplar için yeterli stok bulunmamaktadır. İşlem iptal edildi.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    UPDATE k
    SET k.StokMiktari = k.StokMiktari - i.Adet
    FROM Kitaplar k
    INNER JOIN inserted i ON k.KitapID = i.KitapID;
END;
GO

CREATE TRIGGER trg_SiparisToplamTutarGuncelle
ON SiparisDetaylari
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    WITH EtkilenenSiparisler AS (
        SELECT SiparisID FROM inserted
        UNION
        SELECT SiparisID FROM deleted
    )
    UPDATE s
    SET s.ToplamTutar = ISNULL((
        SELECT SUM(Adet * BirimFiyati)
        FROM SiparisDetaylari sd
        WHERE sd.SiparisID = s.SiparisID
    ), 0)
    FROM Siparisler s
    INNER JOIN EtkilenenSiparisler es ON s.SiparisID = es.SiparisID;
END;
GO

CREATE TRIGGER trg_OdemeAlindiSiparisGuncelle
ON Odemeler
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE s
    SET s.Durum = 'Ödendi'
    FROM Siparisler s
    INNER JOIN inserted i ON s.SiparisID = i.SiparisID;
END;
GO

CREATE VIEW vw_SiparisOzetleri AS
SELECT 
    s.SiparisID,
    u.AdSoyad AS MusteriAdi,
    s.SiparisTarihi,
    s.ToplamTutar,
    s.Durum,
    (SELECT COUNT(*) FROM SiparisDetaylari sd WHERE sd.SiparisID = s.SiparisID) AS FarkliKitapCesidi
FROM Siparisler s
INNER JOIN Kullanicilar u ON s.KullaniciID = u.KullaniciID;
GO