%% ========================================================================
%  SVAR con identificación mixta: Instrumentos Externos + Restricciones de Signo
%  Método: Cesa-Bianchi & Sokol (2021), implementado en el VAR Toolbox
%  (Cesa-Bianchi) mediante VARopt.ident = 'sign+iv'
%
%  Choque de política monetaria  -> identificado con el instrumento externo mps
%  Choques restantes (4)         -> identificados con restricciones de signo,
%                                    condicionales al choque ya fijado por el IV
% ========================================================================

clear; clc; close all;

%% 1) Cargar datos
% ------------------------------------------------------------------------
raw = readcell('data_mensul_exp.xlsx', 'Sheet', 'Hoja1');

% Estructura del archivo:
%   Fila 1: nombres largos (encabezado descriptivo)
%   Fila 2: mnemónicos cortos (igae, inf, cetes28, exp_12m, tc, mps)
%   Fila 3 en adelante: datos, con la fecha en la columna 1 (texto 'YYYYmM')
dates_txt = raw(3:end, 1);                  % fechas (texto), col. 1
data      = cell2mat(raw(3:end, 2:end));    % matriz numérica: igae, inf, cetes28, exp_12m, tc, mps

% Nombres cortos (deben coincidir con el orden de columnas del archivo)
mnem  = {'igae','inf','cetes28','exp_12m','tc','mps'};

igae    = data(:,1);
inf_    = data(:,2);
cetes28 = data(:,3);
exp12m  = data(:,4);
tc      = data(:,5);
mps     = data(:,6);

%% 1.1) Brecha del producto: log(IGAE) + filtro Hodrick-Prescott
% ------------------------------------------------------------------------
% IGAE es un índice en niveles, no la variable a usar directamente en el
% VAR. La brecha del producto es el componente cíclico de log(IGAE) tras
% aplicar el filtro HP.
log_igae  = log(igae);
lambda_hp = 129600;   % valor convencional para datos MENSUALES (Ravn-Uhlig, 2002)
                      % (1600 para trimestral, 6.25 para anual, si cambias de frecuencia)

if exist('hpfilter', 'file') == 2
    % Requiere Econometrics Toolbox
    [trend_igae, gap_igae] = hpfilter(log_igae, 'Smoothing', lambda_hp);
else
    warning(['hpfilter no disponible (requiere Econometrics Toolbox); ' ...
             'usando implementación manual del filtro HP.']);
    [trend_igae, gap_igae] = hp_filter_manual(log_igae, lambda_hp);
end

brecha_producto = gap_igae;   % componente cíclico = brecha del producto

% Chequeo visual rápido (opcional, comenta si no lo necesitas)
figure;
plot(log_igae, 'LineWidth', 1.2); hold on;
plot(trend_igae, 'LineWidth', 1.2, 'LineStyle', '--');
legend('log(IGAE)', 'Tendencia HP', 'Location', 'best');
title('Log(IGAE) y su tendencia HP');
grid on;

% X: SOLO variables endógenas. mps sale de X y entra aparte como instrumento.
X = [brecha_producto, inf_, cetes28, exp12m, tc];
Xmnem  = {'gap','inf','cetes28','exp_12m','tc'};
Xvnames = {'Brecha del Producto','Inflaci\''on','Cetes 28d','Exp. Inflaci\''on 12m','Tipo de cambio'};

nvars = size(X,2);

%% 2) Selección de rezagos
% ------------------------------------------------------------------------
% (usa VARlag.m del toolbox; ajusta pmax según tu frecuencia mensual)
pmax = 12;
disp('--- Selección de rezagos (criterios de información) ---')
VARlag(X, pmax, 1);   % 1 = incluir constante; revisa AIC/BIC/HQ en la salida
nlags = 6;             % <-- AJUSTA con base en el resultado de VARlag
detc  = 1;             % 1 = constante

%% 3) Opciones generales del VAR
% ------------------------------------------------------------------------
VARopt = VARoption;
VARopt.vnames    = Xvnames;
VARopt.mnem      = Xmnem;
VARopt.nsteps    = 24;        % horizonte de los IRF (meses)
VARopt.frequency = 'm';
VARopt.impact    = 0;         % 0 = choque de 1 desv. estándar
VARopt.pctg      = 95;
VARopt.method    = 'wild';
VARopt.inference = 1;
VARopt.ndraws    = 1000;      % número de draws ACEPTADOS que se buscan
VARopt.sr_hor    = 1;         % restricciones de signo se exigen en el impacto (h=0)
% --- Exportación de figuras ---
% quality = 2 (exportgraphics, default): puede fallar en Live Editor si las
%             figuras se muestran "inline" (docked).
% quality = 1 (Ghostscript legacy): requiere la función export_fig.m de
%             terceros (FileExchange) en el path; si no la tienes instalada
%             falla con "Unrecognized function or variable 'export_fig'".
% quality = 0 (print -dpdf): sin dependencias externas, siempre funciona,
%             calidad algo menor. Úsalo si no quieres instalar export_fig.
set(0,'DefaultFigureWindowStyle','normal');   % evita el problema de docking
VARopt.quality   = 0;          % <-- sin dependencias externas; ver notas arriba
VARopt.figname   = 'graphics/svar_sign_iv';

%% 4) Instrumento externo (mps) — diagnóstico de relevancia previo
% ------------------------------------------------------------------------
% mps trae NaN/ceros al inicio de la muestra en muchas aplicaciones; el
% toolbox maneja el recorte internamente, pero conviene revisar la serie:
fprintf('Observaciones de mps: %d, NaNs: %d\n', numel(mps), sum(isnan(mps)));

%% 5) Restricciones de signo para los 4 choques NO identificados por IV
% ------------------------------------------------------------------------
% IMPORTANTE: con ident = 'sign+iv', R tiene dimensión k x (k-1), es decir
% UNA COLUMNA MENOS que en el caso 'sign' puro, porque la columna de
% política monetaria queda fija por el instrumento y no se rota.
%
% Orden de FILAS = orden de variables en X: [brecha_producto, inf, cetes28, exp_12m, tc]
% Orden de COLUMNAS = los 4 choques restantes a identificar por signo:
%   [Oferta, Demanda, Expectativas, Tipo de cambio]
%
% Valores: 1 = positivo, -1 = negativo, 0 = sin restricción
%
%              Oferta  Demanda  Expectativas  TipoCambio
R = [           -1,       1,        0,            0   ;    % brecha_producto
                 1,       1,        0,            1   ;    % inf
                 1,       1,        0,            0   ;    % cetes28 (sin restricción)
                 0,       0,        0,            0   ;    % exp_12m
                 0,       0,        0,            1  ];    % tc

% NOTA: esta matriz es un punto de partida razonable, no una verdad
% teórica única. Ajusta signos/filas según tu marco (p.ej. si crees que un
% choque de demanda también debe subir cetes28, cambia esa celda a 1).

VARopt.snames = {'Pol\''itica Monetaria','Oferta','Demanda','Expectativas','Tipo de Cambio'};

%% 6) Identificación combinada: IV + Sign Restrictions
% ------------------------------------------------------------------------
VARopt.ident = 'sign+iv';
VARopt.IV    = mps;
VARopt.R     = R;

VAR_ivsr = VARmodel(X, nlags, detc, VARopt);

%% 7) Diagnóstico del instrumento (primera etapa)
% ------------------------------------------------------------------------
fprintf('\n--- Diagnóstico del instrumento mps ---\n');
fprintf('F-stat de primera etapa: %.4f\n', VAR_ivsr.FirstStage.F);
if VAR_ivsr.FirstStage.F < 10
    warning(['El F-stat de primera etapa es < 10: el instrumento podría ser ' ...
             'débil (Stock-Yogo). Revisa la construcción de mps.']);
else
    fprintf('El instrumento supera el umbral convencional de F > 10 (relevancia adecuada).\n');
end

fprintf('Tasa de aceptación de la búsqueda de rotaciones (sign): %d de %d draws intentados\n', ...
    VARopt.ndraws, size(VAR_ivsr.Ball,3));

%% 8) Impulse Response Functions
% ------------------------------------------------------------------------
% Choque 1 = Política Monetaria (identificado por IV; NO variará si cambias R)
VARopt.pick = 1;
VARirplot(VAR_ivsr.IRmed, VARopt, VAR_ivsr.IRinf, VAR_ivsr.IRsup);

% Choques 2-5 = identificados por restricciones de signo, condicionales al IV
for s = 2:nvars
    VARopt.pick = s;
    VARirplot(VAR_ivsr.IRmed, VARopt, VAR_ivsr.IRinf, VAR_ivsr.IRsup);
end

%% 9) Descomposición de varianza del error de pronóstico (FEVD)
% ------------------------------------------------------------------------
% USAR VDfp (Fry-Pagan), NUNCA VDmed: solo VDfp garantiza que las
% participaciones sumen exactamente 1 (ver notas de la sesión anterior).
VARopt.vnames = Xvnames;
VARvdplot(VAR_ivsr.VDfp, VARopt);

% Chequeo rápido: las participaciones deben sumar ~1 en cada horizonte/variable
fprintf('\n--- Chequeo de suma de FEVD (debe ser ~1) ---\n');
for i = 1:nvars
    suma_h1 = sum(squeeze(VAR_ivsr.VDfp(1,i,:)));
    fprintf('%s, horizonte 1: suma = %.4f\n', Xmnem{i}, suma_h1);
end

%% 10) Descomposición histórica (Historical Decomposition)
% ------------------------------------------------------------------------
% Igual que en FEVD: usar HDfp, no HDmed.
VARhdplot(VAR_ivsr.HDfp, VARopt);

%% 11) (Opcional) Comparación con tu identificación anterior solo-por-signos
% ------------------------------------------------------------------------
% Útil para ver cuánto cambia la respuesta de política monetaria al pasar
% de "sign puro" a "sign+iv". Requiere tu matriz SIGN de 5x5 anterior.
%
% VARopt.ident = 'sign';
% VARopt.R     = SIGN;      % tu matriz 5x5 anterior
% VAR_sr_only  = VARmodel(X, nlags, detc, VARopt);
% VARopt.pick  = 1;         % elige el índice que corresponda a Cetes/MonPol en SIGN
% VARirplot(VAR_sr_only.IRmed, VARopt, VAR_sr_only.IRinf, VAR_sr_only.IRsup);

disp('--- Listo. Revisa la carpeta graphics/ para las figuras exportadas ---');

%% ========================================================================
%  Funciones locales
% ========================================================================
function [trend, cycle] = hp_filter_manual(y, lambda)
% Implementación manual del filtro Hodrick-Prescott (fallback si no se
% cuenta con Econometrics Toolbox). Resuelve el problema de suavizamiento
% estándar: min_trend  sum((y-trend)^2) + lambda * sum((D^2 trend)^2)
% donde D^2 es el operador de segundas diferencias.
    y = y(:);
    T = length(y);
    D = zeros(T-2, T);
    for i = 1:T-2
        D(i, i)   =  1;
        D(i, i+1) = -2;
        D(i, i+2) =  1;
    end
    A     = eye(T) + lambda * (D' * D);
    trend = A \ y;
    cycle = y - trend;
end