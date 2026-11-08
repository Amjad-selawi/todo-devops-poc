# syntax=docker/dockerfile:1

# ============ Stage 1: build (has the full .NET SDK) ============
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first and restore packages.
# This layer is cached until TodoApi.csproj changes, so code edits rebuild fast.
COPY src/TodoApi/TodoApi.csproj src/TodoApi/
RUN dotnet restore src/TodoApi/TodoApi.csproj

# Now copy the source code and publish a Release build.
COPY src/TodoApi/ src/TodoApi/
RUN dotnet publish src/TodoApi/TodoApi.csproj \
    -c Release -o /app/publish --no-restore /p:UseAppHost=false

# ============ Stage 2: runtime (small image, no SDK, no source code) ============
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Version is passed by the pipeline: docker build --build-arg APP_VERSION=<commit sha>
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    ASPNETCORE_HTTP_PORTS=8080

COPY --from=build /app/publish .

# Run as the non-root user that ships with the official .NET images.
USER $APP_UID

EXPOSE 8080
ENTRYPOINT ["dotnet", "TodoApi.dll"]
