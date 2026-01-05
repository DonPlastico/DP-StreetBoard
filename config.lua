Config = {}
Config.DebugMode = false

-- Detección automática del framework, o fuérzalo aquí ("qb" / "esx")
Config.Framework = "qb"

-- Ajustes Principales
Config.ItemName = 'skateboard'
Config.PhysicsVehicle = 'bmx' -- Vehículo base para las físicas
Config.PropModel = 'p_defilied_ragdoll_01_s' -- Modelo visual del skate

-- Ajustes de Físicas
Config.MaxVelocity = 65 -- Km/h antes de perder el control
Config.JumpForce = 7.0 -- Potencia del salto
Config.DetachDistance = 2.0 -- Distancia máxima antes de que el script asuma que te has alejado del skate
Config.JumpCooldown = 1200 -- Tiempo en milisegundos entre saltos (1.2 segundos)

-- Textos y Notificaciones
Config.Lang = {
    -- Mensajes de Chat/Notify
    ['collected'] = 'Has guardado el skate.',

    -- Etiquetas para DP-TextUI
    ['ui_pickup'] = 'Recoger',
    ['ui_mount'] = 'Patinar',
    ['ui_dismount'] = 'Bajar',
    ['ui_jump'] = 'Saltar'
}
