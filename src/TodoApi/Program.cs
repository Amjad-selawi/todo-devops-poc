using System.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using TodoApi;

var builder = WebApplication.CreateBuilder(args);

// ---------- Database ----------
// The connection string comes from outside the image:
//   Docker Compose -> environment variable
//   Kubernetes     -> Secret
// No connection string (dotnet run / tests) -> in-memory database.
var connectionString = builder.Configuration.GetConnectionString("Default");
if (string.IsNullOrWhiteSpace(connectionString))
    builder.Services.AddDbContext<AppDb>(o => o.UseInMemoryDatabase("todos"));
else
    builder.Services.AddDbContext<AppDb>(o => o.UseNpgsql(connectionString));

// ---------- Health checks (used by Kubernetes probes) ----------
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDb>("database", tags: ["ready"]);

var app = builder.Build();

await DbInit.EnsureDatabaseAsync(app.Services, app.Logger);

// ---------- Info: shows which Pod answered (load balancing demo) ----------
app.MapGet("/", (IConfiguration config, IHostEnvironment env) => Results.Ok(new
{
    app = "todo-api",
    version = config["APP_VERSION"] ?? "dev",
    environment = env.EnvironmentName,
    greeting = config["App:Greeting"] ?? "Hello from .NET",  // from ConfigMap in Kubernetes
    host = Environment.MachineName,                           // = Pod name in Kubernetes
    time = DateTime.UtcNow
}));

// liveness: is the process alive? (never checks the database)
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });

// readiness: can it serve traffic? (checks the database)
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

// ---------- Todo CRUD ----------
var todos = app.MapGroup("/api/todos");

todos.MapGet("/", async (AppDb db) =>
    await db.Todos.OrderBy(t => t.Id).ToListAsync());

todos.MapGet("/{id:int}", async (int id, AppDb db) =>
    await db.Todos.FindAsync(id) is { } todo ? Results.Ok(todo) : Results.NotFound());

todos.MapPost("/", async (TodoInput input, AppDb db) =>
{
    if (string.IsNullOrWhiteSpace(input.Title))
        return Results.BadRequest(new { error = "title is required" });

    var todo = new Todo { Title = input.Title.Trim(), IsDone = input.IsDone };
    db.Todos.Add(todo);
    await db.SaveChangesAsync();
    return Results.Created($"/api/todos/{todo.Id}", todo);
});

todos.MapPut("/{id:int}", async (int id, TodoInput input, AppDb db) =>
{
    if (string.IsNullOrWhiteSpace(input.Title))
        return Results.BadRequest(new { error = "title is required" });

    var todo = await db.Todos.FindAsync(id);
    if (todo is null) return Results.NotFound();

    todo.Title = input.Title.Trim();
    todo.IsDone = input.IsDone;
    await db.SaveChangesAsync();
    return Results.Ok(todo);
});

todos.MapDelete("/{id:int}", async (int id, AppDb db) =>
{
    var todo = await db.Todos.FindAsync(id);
    if (todo is null) return Results.NotFound();

    db.Todos.Remove(todo);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

// ---------- Demo endpoints (turned on by App:EnableChaos) ----------
if (app.Configuration.GetValue<bool>("App:EnableChaos"))
{
    // Burns CPU for N seconds -> makes the HorizontalPodAutoscaler add Pods.
    app.MapGet("/api/stress", (int? seconds) =>
    {
        var duration = Math.Clamp(seconds ?? 10, 1, 30);
        var sw = Stopwatch.StartNew();
        double x = 0;
        while (sw.Elapsed.TotalSeconds < duration) x += Math.Sqrt(sw.ElapsedTicks);
        return Results.Ok(new { burnedSeconds = duration, host = Environment.MachineName });
    });

    // Kills the process -> Kubernetes restarts the container (self-healing).
    app.MapPost("/api/crash", (ILogger<Program> logger) =>
    {
        logger.LogWarning("Crash requested, exiting with code 1");
        _ = Task.Run(async () => { await Task.Delay(200); Environment.Exit(1); });
        return Results.Accepted(value: new { crashing = Environment.MachineName });
    });
}

app.Run();

// Needed so the test project can start the app with WebApplicationFactory.
public partial class Program;
